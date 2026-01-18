//
//  BluetoothTests.swift
//  BluetoothTests
//
//  Created by Edward Chang on 2026/01/17.
//

import Testing
import Combine
import CoreBluetooth
@testable import Bluetooth

// MARK: - Mock CentralManager

class MockCentralManager: CentralManagerProtocol {
    var state: CBManagerState
    var delegate: CBCentralManagerDelegate?

    var scanForPeripheralsCalled = false
    var stopScanCalled = false
    var lastScanServices: [CBUUID]?
    var lastScanOptions: [String: Any]?

    init(state: CBManagerState = .poweredOn) {
        self.state = state
    }

    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?) {
        scanForPeripheralsCalled = true
        lastScanServices = serviceUUIDs
        lastScanOptions = options
    }

    func stopScan() {
        stopScanCalled = true
    }
}

// MARK: - BluetoothManager Tests

struct BluetoothManagerTests {

    // MARK: - 初始化測試

    @Test("初始化時應該設定正確的藍牙狀態")
    func initShouldSetCorrectBluetoothState() {
        let mockManager = MockCentralManager(state: .poweredOn)
        let bluetoothManager = BluetoothManager(centralManager: mockManager)

        #expect(bluetoothManager.bluetoothState == .poweredOn)
    }

    @Test("初始化時裝置列表應該為空")
    func initShouldHaveEmptyDeviceList() {
        let mockManager = MockCentralManager()
        let bluetoothManager = BluetoothManager(centralManager: mockManager)

        #expect(bluetoothManager.discoveredDevices.isEmpty)
    }

    @Test("初始化時不應該在掃描中")
    func initShouldNotBeScanning() {
        let mockManager = MockCentralManager()
        let bluetoothManager = BluetoothManager(centralManager: mockManager)

        #expect(!bluetoothManager.isScanning)
    }

    // MARK: - 掃描測試

    @Test("藍牙開啟時開始掃描應該成功")
    func startScanningShouldWorkWhenBluetoothOn() {
        let mockManager = MockCentralManager(state: .poweredOn)
        let bluetoothManager = BluetoothManager(centralManager: mockManager)

        bluetoothManager.startScanning()

        #expect(bluetoothManager.isScanning)
        #expect(mockManager.scanForPeripheralsCalled)
    }

    @Test("藍牙關閉時開始掃描應該失敗")
    func startScanningShouldFailWhenBluetoothOff() {
        let mockManager = MockCentralManager(state: .poweredOff)
        let bluetoothManager = BluetoothManager(centralManager: mockManager)

        bluetoothManager.startScanning()

        #expect(!bluetoothManager.isScanning)
        #expect(!mockManager.scanForPeripheralsCalled)
    }

    @Test("停止掃描應該呼叫 stopScan")
    func stopScanningShouldCallStopScan() {
        let mockManager = MockCentralManager(state: .poweredOn)
        let bluetoothManager = BluetoothManager(centralManager: mockManager)

        bluetoothManager.startScanning()
        bluetoothManager.stopScanning()

        #expect(!bluetoothManager.isScanning)
        #expect(mockManager.stopScanCalled)
    }

    @Test("開始掃描應該清除之前的裝置")
    func startScanningShouldClearPreviousDevices() {
        let mockManager = MockCentralManager(state: .poweredOn)
        let bluetoothManager = BluetoothManager(centralManager: mockManager)

        // 先添加一些裝置
        let device = PeripheralDevice(id: UUID(), name: "Test", rssi: -50, peripheral: nil)
        bluetoothManager.addDiscoveredDevice(device)
        #expect(bluetoothManager.discoveredDevices.count == 1)

        // 重新掃描
        bluetoothManager.startScanning()

        #expect(bluetoothManager.discoveredDevices.isEmpty)
    }

    // MARK: - 裝置發現測試

    @Test("添加裝置應該加入列表")
    func addDeviceShouldAppendToList() {
        let mockManager = MockCentralManager()
        let bluetoothManager = BluetoothManager(centralManager: mockManager)

        let device = PeripheralDevice(id: UUID(), name: "iPhone", rssi: -60, peripheral: nil)
        bluetoothManager.addDiscoveredDevice(device)

        #expect(bluetoothManager.discoveredDevices.count == 1)
        #expect(bluetoothManager.discoveredDevices.first?.name == "iPhone")
    }

    @Test("重複的裝置不應該被添加")
    func duplicateDeviceShouldNotBeAdded() {
        let mockManager = MockCentralManager()
        let bluetoothManager = BluetoothManager(centralManager: mockManager)

        let deviceId = UUID()
        let device1 = PeripheralDevice(id: deviceId, name: "iPhone", rssi: -60, peripheral: nil)
        let device2 = PeripheralDevice(id: deviceId, name: "iPhone", rssi: -55, peripheral: nil)

        bluetoothManager.addDiscoveredDevice(device1)
        bluetoothManager.addDiscoveredDevice(device2)

        #expect(bluetoothManager.discoveredDevices.count == 1)
    }

    @Test("裝置應該依照訊號強度排序")
    func devicesShouldBeSortedByRSSI() {
        let mockManager = MockCentralManager()
        let bluetoothManager = BluetoothManager(centralManager: mockManager)

        let weakDevice = PeripheralDevice(id: UUID(), name: "Weak", rssi: -90, peripheral: nil)
        let strongDevice = PeripheralDevice(id: UUID(), name: "Strong", rssi: -40, peripheral: nil)
        let mediumDevice = PeripheralDevice(id: UUID(), name: "Medium", rssi: -60, peripheral: nil)

        bluetoothManager.addDiscoveredDevice(weakDevice)
        bluetoothManager.addDiscoveredDevice(strongDevice)
        bluetoothManager.addDiscoveredDevice(mediumDevice)

        #expect(bluetoothManager.discoveredDevices[0].name == "Strong")
        #expect(bluetoothManager.discoveredDevices[1].name == "Medium")
        #expect(bluetoothManager.discoveredDevices[2].name == "Weak")
    }

    // MARK: - 藍牙狀態測試

    @Test("更新藍牙狀態應該更新 bluetoothState")
    func updateStateShouldUpdateBluetoothState() {
        let mockManager = MockCentralManager(state: .unknown)
        let bluetoothManager = BluetoothManager(centralManager: mockManager)

        bluetoothManager.updateBluetoothState(.poweredOn)
        #expect(bluetoothManager.bluetoothState == .poweredOn)

        bluetoothManager.updateBluetoothState(.poweredOff)
        #expect(bluetoothManager.bluetoothState == .poweredOff)
    }

    @Test("藍牙關閉時應該停止掃描")
    func bluetoothOffShouldStopScanning() {
        let mockManager = MockCentralManager(state: .poweredOn)
        let bluetoothManager = BluetoothManager(centralManager: mockManager)

        bluetoothManager.startScanning()
        #expect(bluetoothManager.isScanning)

        bluetoothManager.updateBluetoothState(.poweredOff)

        #expect(!bluetoothManager.isScanning)
    }

    // MARK: - 狀態描述測試

    @Test("stateDescription 應該回傳正確的中文描述")
    func stateDescriptionShouldReturnCorrectChinese() {
        let mockManager = MockCentralManager()
        let bluetoothManager = BluetoothManager(centralManager: mockManager)

        bluetoothManager.updateBluetoothState(.poweredOn)
        #expect(bluetoothManager.stateDescription == "藍牙已開啟")

        bluetoothManager.updateBluetoothState(.poweredOff)
        #expect(bluetoothManager.stateDescription == "藍牙已關閉")

        bluetoothManager.updateBluetoothState(.unauthorized)
        #expect(bluetoothManager.stateDescription == "請授權藍牙權限")

        bluetoothManager.updateBluetoothState(.unsupported)
        #expect(bluetoothManager.stateDescription == "此裝置不支援藍牙")
    }
}

// MARK: - PeripheralDevice Tests

struct PeripheralDeviceTests {

    @Test("訊號強度強應該顯示「強」")
    func strongSignalShouldShowStrong() {
        let device = PeripheralDevice(id: UUID(), name: "Test", rssi: -45, peripheral: nil)
        #expect(device.signalStrength == "強")
    }

    @Test("訊號強度中應該顯示「中」")
    func mediumSignalShouldShowMedium() {
        let device = PeripheralDevice(id: UUID(), name: "Test", rssi: -60, peripheral: nil)
        #expect(device.signalStrength == "中")
    }

    @Test("訊號強度弱應該顯示「弱」")
    func weakSignalShouldShowWeak() {
        let device = PeripheralDevice(id: UUID(), name: "Test", rssi: -80, peripheral: nil)
        #expect(device.signalStrength == "弱")
    }

    @Test("RSSI -50 應該是強訊號的邊界")
    func rssiMinus50ShouldBeStrongBoundary() {
        let device = PeripheralDevice(id: UUID(), name: "Test", rssi: -50, peripheral: nil)
        #expect(device.signalStrength == "強")
    }

    @Test("RSSI -51 應該是中訊號")
    func rssiMinus51ShouldBeMedium() {
        let device = PeripheralDevice(id: UUID(), name: "Test", rssi: -51, peripheral: nil)
        #expect(device.signalStrength == "中")
    }
}

// MARK: - Combine @Published Tests

struct CombinePublishedTests {

    @Test("@Published isScanning 變化應該被發布")
    func isScanningChangeShouldBePublished() async {
        let mockManager = MockCentralManager(state: .poweredOn)
        let bluetoothManager = BluetoothManager(centralManager: mockManager)

        var receivedValues: [Bool] = []
        let cancellable = bluetoothManager.$isScanning
            .sink { value in
                receivedValues.append(value)
            }

        bluetoothManager.startScanning()
        bluetoothManager.stopScanning()

        // 初始值 false, startScanning 設為 true, stopScanning 設為 false
        #expect(receivedValues == [false, true, false])

        cancellable.cancel()
    }

    @Test("@Published discoveredDevices 變化應該被發布")
    func discoveredDevicesChangeShouldBePublished() async {
        let mockManager = MockCentralManager()
        let bluetoothManager = BluetoothManager(centralManager: mockManager)

        var publishCount = 0
        let cancellable = bluetoothManager.$discoveredDevices
            .sink { _ in
                publishCount += 1
            }

        let device = PeripheralDevice(id: UUID(), name: "Test", rssi: -50, peripheral: nil)
        bluetoothManager.addDiscoveredDevice(device)

        // 初始發布 + append + sort = 3 次
        #expect(publishCount >= 2)

        cancellable.cancel()
    }
}
