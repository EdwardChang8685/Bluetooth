//
//  BluetoothManager.swift
//  Bluetooth
//
//  Created by Edward Chang on 2026/01/17.
//

import Foundation
import CoreBluetooth
import Combine

// MARK: - 資料模型

/// 代表一個發現的藍牙周邊裝置
struct PeripheralDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral?

    var signalStrength: String {
        switch rssi {
        case -50...0:
            return "強"
        case -70..<(-50):
            return "中"
        default:
            return "弱"
        }
    }

    static func == (lhs: PeripheralDevice, rhs: PeripheralDevice) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.rssi == rhs.rssi
    }
}

/// 代表一個 BLE 服務
struct BLEService: Identifiable {
    let id: String
    let uuid: CBUUID
    let name: String
    var characteristics: [BLECharacteristic]

    init(service: CBService) {
        self.id = service.uuid.uuidString
        self.uuid = service.uuid
        self.name = Self.getServiceName(uuid: service.uuid)
        self.characteristics = []
    }

    static func getServiceName(uuid: CBUUID) -> String {
        // 標準 BLE 服務名稱
        let standardServices: [String: String] = [
            "180D": "心率服務",
            "180F": "電池服務",
            "180A": "裝置資訊",
            "1800": "通用存取",
            "1801": "通用屬性",
            "1802": "立即警報",
            "1803": "連結遺失",
            "1804": "發射功率",
            "1805": "當前時間",
            "1806": "參考時間更新",
            "1807": "下一個 DST 變更",
            "1808": "葡萄糖",
            "1809": "健康溫度計",
            "181C": "使用者資料",
            "181D": "體重秤"
        ]
        return standardServices[uuid.uuidString] ?? "自訂服務"
    }
}

/// 代表一個 BLE 特徵
struct BLECharacteristic: Identifiable {
    let id: String
    let uuid: CBUUID
    let name: String
    let properties: CBCharacteristicProperties
    let characteristic: CBCharacteristic

    var canRead: Bool { properties.contains(.read) }
    var canWrite: Bool { properties.contains(.write) || properties.contains(.writeWithoutResponse) }
    var canNotify: Bool { properties.contains(.notify) || properties.contains(.indicate) }

    var propertiesDescription: String {
        var props: [String] = []
        if canRead { props.append("讀取") }
        if canWrite { props.append("寫入") }
        if canNotify { props.append("通知") }
        return props.joined(separator: ", ")
    }

    init(characteristic: CBCharacteristic) {
        self.id = characteristic.uuid.uuidString
        self.uuid = characteristic.uuid
        self.name = Self.getCharacteristicName(uuid: characteristic.uuid)
        self.properties = characteristic.properties
        self.characteristic = characteristic
    }

    static func getCharacteristicName(uuid: CBUUID) -> String {
        let standardCharacteristics: [String: String] = [
            "2A37": "心率測量",
            "2A38": "感測器位置",
            "2A39": "心率控制點",
            "2A19": "電池電量",
            "2A29": "製造商名稱",
            "2A24": "型號",
            "2A25": "序號",
            "2A26": "韌體版本",
            "2A27": "硬體版本",
            "2A28": "軟體版本"
        ]
        return standardCharacteristics[uuid.uuidString] ?? "自訂特徵"
    }
}

// MARK: - 連線狀態

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case discoveringServices
    case ready

    var description: String {
        switch self {
        case .disconnected: return "未連線"
        case .connecting: return "連線中..."
        case .connected: return "已連線"
        case .discoveringServices: return "探索服務中..."
        case .ready: return "準備就緒"
        }
    }
}

// MARK: - Protocol 抽象化

protocol CentralManagerProtocol {
    var state: CBManagerState { get }
    var delegate: CBCentralManagerDelegate? { get set }
    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?)
    func stopScan()
    func connect(_ peripheral: CBPeripheral, options: [String: Any]?)
    func cancelPeripheralConnection(_ peripheral: CBPeripheral)
}

extension CBCentralManager: CentralManagerProtocol {}

// MARK: - BluetoothManager

/// 藍牙管理器，負責掃描、連線、讀寫藍牙裝置
class BluetoothManager: NSObject, ObservableObject {
    // MARK: - Published 屬性

    @Published var discoveredDevices: [PeripheralDevice] = []
    @Published var isScanning = false
    @Published var bluetoothState: CBManagerState = .unknown

    // 連線相關
    @Published var connectionState: ConnectionState = .disconnected
    @Published var connectedDevice: PeripheralDevice?
    @Published var discoveredServices: [BLEService] = []

    // 資料相關
    @Published var lastReadValue: Data?
    @Published var lastReadString: String?
    @Published var notificationValues: [String: Data] = [:]
    @Published var errorMessage: String?

    // MARK: - Private 屬性

    private var centralManager: CentralManagerProtocol?
    private var discoveredPeripherals: Set<UUID> = []
    private var connectedPeripheral: CBPeripheral?

    // MARK: - 初始化

    init(centralManager: CentralManagerProtocol?) {
        super.init()
        self.centralManager = centralManager
        if var manager = centralManager {
            manager.delegate = self
        }
        if let manager = centralManager {
            self.bluetoothState = manager.state
        }
    }

    override convenience init() {
        self.init(centralManager: nil)
        let manager = CBCentralManager(delegate: self, queue: nil)
        self.centralManager = manager
    }

    // MARK: - 掃描

    func startScanning() {
        guard let manager = centralManager,
              manager.state == .poweredOn else {
            return
        }


        discoveredDevices.removeAll()
        discoveredPeripherals.removeAll()

        isScanning = true
        manager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func stopScanning() {
        centralManager?.stopScan()
        isScanning = false
    }

    // MARK: - 連線

    /// 連線到指定裝置
    func connect(to device: PeripheralDevice) {
        guard let peripheral = device.peripheral else {
            errorMessage = "無效的裝置"
            return
        }

        stopScanning()
        connectionState = .connecting
        connectedDevice = device

        peripheral.delegate = self
        centralManager?.connect(peripheral, options: nil)
    }

    /// 中斷連線
    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }

        centralManager?.cancelPeripheralConnection(peripheral)
        cleanupConnection()
    }

    private func cleanupConnection() {
        connectedPeripheral = nil
        connectedDevice = nil
        connectionState = .disconnected
        discoveredServices.removeAll()
        lastReadValue = nil
        lastReadString = nil
        notificationValues.removeAll()
    }

    // MARK: - 服務探索

    /// 探索裝置的所有服務
    func discoverServices() {
        guard let peripheral = connectedPeripheral else { return }

        connectionState = .discoveringServices
        peripheral.discoverServices(nil) // nil = 探索所有服務
    }

    /// 探索指定服務的特徵
    func discoverCharacteristics(for service: CBService) {
        guard let peripheral = connectedPeripheral else { return }

        peripheral.discoverCharacteristics(nil, for: service)
    }

    // MARK: - 讀取資料

    /// 讀取特徵的值
    func readValue(from characteristic: BLECharacteristic) {
        guard let peripheral = connectedPeripheral,
              characteristic.canRead else {
            errorMessage = "無法讀取此特徵"
            return
        }

        peripheral.readValue(for: characteristic.characteristic)
    }

    // MARK: - 寫入資料

    /// 寫入資料到特徵
    func writeValue(_ data: Data, to characteristic: BLECharacteristic) {
        guard let peripheral = connectedPeripheral,
              characteristic.canWrite else {
            errorMessage = "無法寫入此特徵"
            return
        }

        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write)
            ? .withResponse
            : .withoutResponse

        peripheral.writeValue(data, for: characteristic.characteristic, type: type)
    }

    /// 寫入字串到特徵
    func writeString(_ string: String, to characteristic: BLECharacteristic) {
        guard let data = string.data(using: .utf8) else {
            errorMessage = "無法轉換字串為資料"
            return
        }
        writeValue(data, to: characteristic)
    }

    /// 寫入十六進位字串到特徵
    func writeHexString(_ hexString: String, to characteristic: BLECharacteristic) {
        let cleanHex = hexString.replacingOccurrences(of: " ", with: "")
        guard let data = Data(hexString: cleanHex) else {
            errorMessage = "無效的十六進位字串"
            return
        }
        writeValue(data, to: characteristic)
    }

    // MARK: - 通知

    /// 開啟/關閉特徵的通知
    func setNotification(enabled: Bool, for characteristic: BLECharacteristic) {
        guard let peripheral = connectedPeripheral,
              characteristic.canNotify else {
            errorMessage = "此特徵不支援通知"
            return
        }

        peripheral.setNotifyValue(enabled, for: characteristic.characteristic)
    }

    // MARK: - 輔助方法

    func addDiscoveredDevice(_ device: PeripheralDevice) {
        guard !discoveredPeripherals.contains(device.id) else { return }
        discoveredPeripherals.insert(device.id)
        discoveredDevices.append(device)
        discoveredDevices.sort { $0.rssi > $1.rssi }
    }

    func updateBluetoothState(_ state: CBManagerState) {
        bluetoothState = state
        if state != .poweredOn {
            stopScanning()
        }
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

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateBluetoothState(central.state)
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let deviceName = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "未知裝置"

        let device = PeripheralDevice(
            id: peripheral.identifier,
            name: deviceName,
            rssi: RSSI.intValue,
            peripheral: peripheral
        )
        addDiscoveredDevice(device)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        connectionState = .connected
        errorMessage = nil

        // 自動探索服務
        discoverServices()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        errorMessage = "連線失敗: \(error?.localizedDescription ?? "未知錯誤")"
        cleanupConnection()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            errorMessage = "連線中斷: \(error.localizedDescription)"
        }
        cleanupConnection()
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    // 發現服務
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            errorMessage = "探索服務失敗: \(error.localizedDescription)"
            return
        }

        guard let services = peripheral.services else { return }

        discoveredServices = services.map { BLEService(service: $0) }
        connectionState = .ready

        // 自動探索每個服務的特徵
        for service in services {
            discoverCharacteristics(for: service)
        }
    }

    // 發現特徵
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            errorMessage = "探索特徵失敗: \(error.localizedDescription)"
            return
        }

        guard let characteristics = service.characteristics else { return }

        // 更新對應服務的特徵列表
        if let index = discoveredServices.firstIndex(where: { $0.uuid == service.uuid }) {
            discoveredServices[index].characteristics = characteristics.map {
                BLECharacteristic(characteristic: $0)
            }
        }
    }

    // 讀取特徵值
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            errorMessage = "讀取失敗: \(error.localizedDescription)"
            return
        }

        guard let data = characteristic.value else { return }

        lastReadValue = data
        lastReadString = String(data: data, encoding: .utf8)

        // 如果是通知，也儲存到通知字典
        if characteristic.isNotifying {
            notificationValues[characteristic.uuid.uuidString] = data
        }
    }

    // 寫入完成
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            errorMessage = "寫入失敗: \(error.localizedDescription)"
        } else {
            errorMessage = nil
        }
    }

    // 通知狀態改變
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            errorMessage = "設定通知失敗: \(error.localizedDescription)"
        }
    }
}

// MARK: - Data Extension

extension Data {
    /// 從十六進位字串建立 Data
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex

        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }

    /// 轉換為十六進位字串
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
