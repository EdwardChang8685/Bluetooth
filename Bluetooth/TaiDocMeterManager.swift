//
//  TaiDocMeterManager.swift
//  Bluetooth
//
//  Created by Edward Chang on 2026/03/05.
//

import Foundation
import CoreBluetooth
import Combine

// MARK: - 資料模型

/// 已配對的 TaiDoc 儀器資訊
struct PairedMeter: Identifiable, Codable, Equatable {
    let id: String       // CBPeripheral UUID
    var name: String     // 使用者可自訂名稱
    let originalName: String  // 原始 BLE 名稱

    static func == (lhs: PairedMeter, rhs: PairedMeter) -> Bool {
        lhs.id == rhs.id
    }
}

/// 掃描中發現的 TaiDoc 裝置
struct DiscoveredMeter: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral

    static func == (lhs: DiscoveredMeter, rhs: DiscoveredMeter) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 連線狀態

enum MeterConnectionState: Equatable {
    case idle
    case scanning
    case connecting
    case connected
    case ready

    var description: String {
        switch self {
        case .idle: return "待機"
        case .scanning: return "掃描中..."
        case .connecting: return "連線中..."
        case .connected: return "已連線"
        case .ready: return "準備就緒"
        }
    }

    var isActive: Bool {
        switch self {
        case .idle: return false
        default: return true
        }
    }
}

// MARK: - TaiDocMeterManager

/// TaiDoc 儀器管理器，負責掃描、配對儲存、GATT 連線
class TaiDocMeterManager: NSObject, ObservableObject {

    // MARK: - 常數

    static let maxPairedMeters = 10
    static let scanDuration: TimeInterval = 10
    static let connectTimeout: TimeInterval = 10

    /// TaiDoc 儀器名稱關鍵字（不分大小寫）
    static let taiDocNameKeywords = ["taidoc", "td", "tng", "fora", "bpm", "bgm"]

    /// UserDefaults key
    private static let pairedMetersKey = "TaiDoc_PairedMeters"

    // MARK: - Published 屬性

    @Published var connectionState: MeterConnectionState = .idle
    @Published var discoveredMeters: [DiscoveredMeter] = []
    @Published var pairedMeters: [PairedMeter] = []
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var errorMessage: String?
    @Published var connectedMeterName: String?

    /// 連線後探索到的 Services
    @Published var discoveredServices: [BLEService] = []

    /// 通知接收到的資料
    @Published var receivedData: [Data] = []

    // MARK: - Private 屬性

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var discoveredPeripheralRefs: [UUID: CBPeripheral] = [:]
    private var scanTimer: DispatchWorkItem?
    private var connectTimer: DispatchWorkItem?

    // MARK: - 初始化

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        loadPairedMeters()
    }

    // MARK: - 掃描

    /// 開始掃描 TaiDoc 儀器（限時 10 秒）
    func startScan() {
        guard centralManager.state == .poweredOn else {
            errorMessage = "藍牙未開啟"
            return
        }
        guard connectionState == .idle else { return }

        discoveredMeters.removeAll()
        discoveredPeripheralRefs.removeAll()
        connectionState = .scanning
        errorMessage = nil

        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        // 掃描計時器
        let timer = DispatchWorkItem { [weak self] in
            self?.stopScan()
        }
        scanTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scanDuration, execute: timer)
    }

    /// 停止掃描
    func stopScan() {
        scanTimer?.cancel()
        scanTimer = nil
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = .idle
        }
    }

    // MARK: - 配對管理

    /// 將發現的裝置加入已配對清單
    func addToPaired(_ meter: DiscoveredMeter) {
        guard pairedMeters.count < Self.maxPairedMeters else {
            errorMessage = "已配對儀器數量已達上限（\(Self.maxPairedMeters) 台）"
            return
        }

        let paired = PairedMeter(
            id: meter.id.uuidString,
            name: meter.name,
            originalName: meter.name
        )

        // 避免重複
        guard !pairedMeters.contains(where: { $0.id == paired.id }) else {
            errorMessage = "此儀器已在配對清單中"
            return
        }

        pairedMeters.append(paired)
        savePairedMeters()
    }

    /// 從已配對清單移除（供 SwiftUI onDelete 使用）
    func removePairedMeters(at offsets: IndexSet) {
        let idsToRemove = offsets.map { pairedMeters[$0].id }
        pairedMeters.removeAll { idsToRemove.contains($0.id) }
        savePairedMeters()
    }

    /// 移除指定儀器
    func removePairedMeter(_ meter: PairedMeter) {
        pairedMeters.removeAll { $0.id == meter.id }
        savePairedMeters()
    }

    /// 重新命名已配對儀器
    func renamePairedMeter(_ meter: PairedMeter, to newName: String) {
        guard let index = pairedMeters.firstIndex(where: { $0.id == meter.id }) else { return }
        pairedMeters[index].name = newName
        savePairedMeters()
    }

    // MARK: - 連線

    /// 連線到指定已配對儀器
    func connectToMeter(_ meter: PairedMeter) {
        guard centralManager.state == .poweredOn else {
            errorMessage = "藍牙未開啟"
            return
        }

        stopScan()
        connectionState = .scanning
        connectedMeterName = meter.name
        errorMessage = nil

        // 掃描尋找該已配對裝置
        let targetUUID = UUID(uuidString: meter.id)
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        // 連線逾時
        let timer = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.connectionState == .scanning || self.connectionState == .connecting {
                self.centralManager.stopScan()
                self.connectionState = .idle
                self.connectedMeterName = nil
                self.errorMessage = "連線逾時，請確認儀器已開機"
            }
        }
        connectTimer = timer

        // 若已知 UUID，嘗試用 retrievePeripherals 直接取得
        if let uuid = targetUUID {
            let knownPeripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
            if let peripheral = knownPeripherals.first {
                centralManager.stopScan()
                connectToPeripheral(peripheral)
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectTimeout, execute: timer)
                return
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectTimeout, execute: timer)
    }

    /// 監聽模式：掃描所有已配對儀器，發現後自動連線
    func listenForPairedMeters() {
        guard centralManager.state == .poweredOn else {
            errorMessage = "藍牙未開啟"
            return
        }
        guard !pairedMeters.isEmpty else {
            errorMessage = "尚無已配對儀器"
            return
        }

        stopScan()
        connectionState = .scanning
        errorMessage = nil

        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        // 掃描逾時
        let timer = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.connectionState == .scanning {
                self.centralManager.stopScan()
                self.connectionState = .idle
                self.errorMessage = "未發現已配對的儀器"
            }
        }
        scanTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scanDuration, execute: timer)
    }

    /// 中斷連線
    func disconnect() {
        connectTimer?.cancel()
        connectTimer = nil
        scanTimer?.cancel()
        scanTimer = nil

        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        cleanupConnection()
    }

    // MARK: - Private 連線方法

    private func connectToPeripheral(_ peripheral: CBPeripheral) {
        connectionState = .connecting
        peripheral.delegate = self
        connectedPeripheral = peripheral
        centralManager.connect(peripheral, options: nil)
    }

    private func cleanupConnection() {
        connectedPeripheral = nil
        connectedMeterName = nil
        connectionState = .idle
        discoveredServices.removeAll()
        receivedData.removeAll()
    }

    // MARK: - 持久儲存

    private func loadPairedMeters() {
        guard let data = UserDefaults.standard.data(forKey: Self.pairedMetersKey),
              let meters = try? JSONDecoder().decode([PairedMeter].self, from: data) else {
            return
        }
        pairedMeters = meters
    }

    private func savePairedMeters() {
        guard let data = try? JSONEncoder().encode(pairedMeters) else { return }
        UserDefaults.standard.set(data, forKey: Self.pairedMetersKey)
    }

    // MARK: - 輔助方法

    /// 判斷裝置名稱是否為 TaiDoc 系列
    static func isTaiDocDevice(name: String?) -> Bool {
        guard let name = name?.lowercased() else { return false }
        return taiDocNameKeywords.contains { name.contains($0) }
    }

    var stateDescription: String {
        switch bluetoothState {
        case .unknown: return "未知狀態"
        case .resetting: return "重置中..."
        case .unsupported: return "此裝置不支援藍牙"
        case .unauthorized: return "請授權藍牙權限"
        case .poweredOff: return "藍牙已關閉"
        case .poweredOn: return "藍牙已開啟"
        @unknown default: return "未知狀態"
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension TaiDocMeterManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        if central.state != .poweredOn {
            stopScan()
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let deviceName = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String

        // 如果是監聽模式或指定連線，檢查是否為已配對裝置
        if connectionState == .scanning && connectedMeterName != nil {
            // 指定連線模式 — 這裡由 connectToMeter 的 retrievePeripherals 處理
            // 但若 retrievePeripherals 失敗，透過掃描找到也要處理
            let matchesPaired = pairedMeters.contains {
                $0.id == peripheral.identifier.uuidString
            }
            if matchesPaired {
                centralManager.stopScan()
                scanTimer?.cancel()
                connectToPeripheral(peripheral)
                return
            }
        }

        // 監聽模式 — 自動連線已配對裝置
        if connectionState == .scanning && connectedMeterName == nil {
            let isPaired = pairedMeters.contains {
                $0.id == peripheral.identifier.uuidString
            }
            if isPaired {
                centralManager.stopScan()
                scanTimer?.cancel()
                connectedMeterName = pairedMeters.first {
                    $0.id == peripheral.identifier.uuidString
                }?.name
                connectToPeripheral(peripheral)
                return
            }
        }

        // 一般掃描模式 — 過濾 TaiDoc 裝置
        guard Self.isTaiDocDevice(name: deviceName) else { return }
        guard !discoveredPeripheralRefs.keys.contains(peripheral.identifier) else { return }

        discoveredPeripheralRefs[peripheral.identifier] = peripheral

        let meter = DiscoveredMeter(
            id: peripheral.identifier,
            name: deviceName ?? "未知 TaiDoc 裝置",
            rssi: RSSI.intValue,
            peripheral: peripheral
        )
        discoveredMeters.append(meter)
        discoveredMeters.sort { $0.rssi > $1.rssi }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectTimer?.cancel()
        connectTimer = nil
        connectionState = .connected
        errorMessage = nil

        // 自動探索 Services
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectTimer?.cancel()
        connectTimer = nil
        errorMessage = "連線失敗: \(error?.localizedDescription ?? "未知錯誤")"
        cleanupConnection()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectTimer?.cancel()
        connectTimer = nil
        if let error = error {
            errorMessage = "連線中斷: \(error.localizedDescription)"
        }
        cleanupConnection()
    }
}

// MARK: - CBPeripheralDelegate

extension TaiDocMeterManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            errorMessage = "探索服務失敗: \(error.localizedDescription)"
            return
        }

        guard let services = peripheral.services else { return }

        discoveredServices = services.map { BLEService(service: $0) }
        connectionState = .ready

        // 探索每個服務的特徵
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            errorMessage = "探索特徵失敗: \(error.localizedDescription)"
            return
        }

        guard let characteristics = service.characteristics else { return }

        if let index = discoveredServices.firstIndex(where: { $0.uuid == service.uuid }) {
            discoveredServices[index].characteristics = characteristics.map {
                BLECharacteristic(characteristic: $0)
            }
        }

        // 自動訂閱所有 Notify 特徵
        for characteristic in characteristics {
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            errorMessage = "接收資料失敗: \(error.localizedDescription)"
            return
        }

        guard let data = characteristic.value else { return }
        receivedData.append(data)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            errorMessage = "訂閱通知失敗: \(error.localizedDescription)"
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            errorMessage = "寫入失敗: \(error.localizedDescription)"
        }
    }
}
