//
//  ContentView.swift
//  Bluetooth
//
//  Created by Edward Chang on 2026/01/17.
//

import SwiftUI
import CoreBluetooth
import Combine

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @State private var selectedDevice: PeripheralDevice?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 藍牙狀態顯示
                StatusView(manager: bluetoothManager)

                // 主要內容
                if bluetoothManager.connectionState != .disconnected {
                    // 已連線：顯示裝置詳情
                    DeviceDetailView(manager: bluetoothManager)
                } else {
                    // 未連線：顯示掃描列表
                    ScanListView(
                        manager: bluetoothManager,
                        onDeviceSelected: { device in
                            bluetoothManager.connect(to: device)
                        }
                    )
                }
            }
            .navigationTitle(bluetoothManager.connectionState == .disconnected ? "藍牙掃描器" : "裝置詳情")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if bluetoothManager.connectionState == .disconnected {
                        ScanButton(manager: bluetoothManager)
                    } else {
                        Button("中斷連線") {
                            bluetoothManager.disconnect()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .alert("錯誤", isPresented: .init(
                get: { bluetoothManager.errorMessage != nil },
                set: { if !$0 { bluetoothManager.errorMessage = nil } }
            )) {
                Button("確定", role: .cancel) {}
            } message: {
                Text(bluetoothManager.errorMessage ?? "")
            }
        }
    }
}

// MARK: - 掃描列表視圖

struct ScanListView: View {
    @ObservedObject var manager: BluetoothManager
    let onDeviceSelected: (PeripheralDevice) -> Void

    var body: some View {
        if manager.discoveredDevices.isEmpty {
            EmptyStateView(isScanning: manager.isScanning)
        } else {
            List(manager.discoveredDevices) { device in
                Button {
                    onDeviceSelected(device)
                } label: {
                    DeviceRowView(device: device)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - 裝置詳情視圖

struct DeviceDetailView: View {
    @ObservedObject var manager: BluetoothManager

    var body: some View {
        List {
            // 連線狀態區塊
            Section("連線狀態") {
                HStack {
                    Text(manager.connectedDevice?.name ?? "未知裝置")
                        .font(.headline)
                    Spacer()
                    Text(manager.connectionState.description)
                        .foregroundColor(.secondary)
                }
            }

            // 服務與特徵區塊
            if manager.connectionState == .ready {
                ForEach(manager.discoveredServices) { service in
                    Section(service.name + " (\(service.uuid.uuidString))") {
                        ForEach(service.characteristics) { characteristic in
                            CharacteristicRowView(
                                characteristic: characteristic,
                                manager: manager
                            )
                        }
                    }
                }
            } else {
                Section {
                    HStack {
                        ProgressView()
                        Text("探索服務中...")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // 最後讀取的資料
            if let data = manager.lastReadValue {
                Section("最後讀取的資料") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HEX: \(data.hexString)")
                            .font(.system(.caption, design: .monospaced))
                        if let string = manager.lastReadString {
                            Text("字串: \(string)")
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 特徵列視圖

struct CharacteristicRowView: View {
    let characteristic: BLECharacteristic
    @ObservedObject var manager: BluetoothManager
    @State private var showWriteSheet = false
    @State private var isNotifying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 特徵名稱和 UUID
            Text(characteristic.name)
                .font(.headline)
            Text(characteristic.uuid.uuidString)
                .font(.caption)
                .foregroundColor(.secondary)

            // 屬性標籤
            Text(characteristic.propertiesDescription)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)

            // 操作按鈕
            HStack(spacing: 12) {
                if characteristic.canRead {
                    Button("讀取") {
                        manager.readValue(from: characteristic)
                    }
                    .buttonStyle(.bordered)
                }

                if characteristic.canWrite {
                    Button("寫入") {
                        showWriteSheet = true
                    }
                    .buttonStyle(.bordered)
                }

                if characteristic.canNotify {
                    Button(isNotifying ? "停止通知" : "開啟通知") {
                        isNotifying.toggle()
                        manager.setNotification(enabled: isNotifying, for: characteristic)
                    }
                    .buttonStyle(.bordered)
                    .tint(isNotifying ? .red : .green)
                }
            }

            // 顯示通知的值
            if isNotifying, let data = manager.notificationValues[characteristic.id] {
                Text("通知值: \(data.hexString)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showWriteSheet) {
            WriteDataSheet(characteristic: characteristic, manager: manager)
        }
    }
}

// MARK: - 寫入資料表單

struct WriteDataSheet: View {
    let characteristic: BLECharacteristic
    @ObservedObject var manager: BluetoothManager
    @Environment(\.dismiss) private var dismiss

    @State private var inputType = 0  // 0: 字串, 1: HEX
    @State private var inputText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("輸入類型") {
                    Picker("類型", selection: $inputType) {
                        Text("字串").tag(0)
                        Text("HEX").tag(1)
                    }
                    .pickerStyle(.segmented)
                }

                Section(inputType == 0 ? "輸入字串" : "輸入 HEX (例如: 01 02 0A FF)") {
                    TextField(inputType == 0 ? "Hello" : "01 02 0A FF", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                }

                Section {
                    Button("送出") {
                        if inputType == 0 {
                            manager.writeString(inputText, to: characteristic)
                        } else {
                            manager.writeHexString(inputText, to: characteristic)
                        }
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(inputText.isEmpty)
                }
            }
            .navigationTitle("寫入資料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 狀態顯示視圖

struct StatusView: View {
    @ObservedObject var manager: BluetoothManager

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)

            Text(manager.stateDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            if manager.isScanning {
                ProgressView()
                    .scaleEffect(0.8)
                Text("掃描中...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }

    private var statusColor: Color {
        switch manager.bluetoothState {
        case .poweredOn:
            return .green
        case .poweredOff:
            return .red
        case .unauthorized:
            return .orange
        default:
            return .gray
        }
    }
}

// MARK: - 空狀態視圖

struct EmptyStateView: View {
    let isScanning: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundColor(.blue.opacity(0.6))

            if isScanning {
                Text("正在搜尋附近的藍牙裝置...")
                    .font(.headline)
                    .foregroundColor(.secondary)
            } else {
                Text("點擊右上角的掃描按鈕\n開始搜尋藍牙裝置")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 單一裝置列視圖

struct DeviceRowView: View {
    let device: PeripheralDevice

    var body: some View {
        HStack(spacing: 12) {
            SignalStrengthView(rssi: device.rssi)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)

                Text("UUID: \(device.id.uuidString.prefix(8))...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(device.rssi) dBm")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(device.signalStrength)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(signalColor.opacity(0.2))
                    .foregroundColor(signalColor)
                    .cornerRadius(4)
            }

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var signalColor: Color {
        switch device.rssi {
        case -50...0:
            return .green
        case -70..<(-50):
            return .orange
        default:
            return .red
        }
    }
}

// MARK: - 訊號強度視圖

struct SignalStrengthView: View {
    let rssi: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index))
                    .frame(width: 4, height: CGFloat(8 + index * 4))
            }
        }
        .frame(width: 24, height: 24, alignment: .bottom)
    }

    private func barColor(for index: Int) -> Color {
        let strength = signalLevel
        if index < strength {
            return .blue
        }
        return .gray.opacity(0.3)
    }

    private var signalLevel: Int {
        switch rssi {
        case -50...0:
            return 4
        case -60..<(-50):
            return 3
        case -70..<(-60):
            return 2
        case -80..<(-70):
            return 1
        default:
            return 0
        }
    }
}

// MARK: - 掃描按鈕

struct ScanButton: View {
    @ObservedObject var manager: BluetoothManager

    var body: some View {
        Button {
            if manager.isScanning {
                manager.stopScanning()
            } else {
                manager.startScanning()
            }
        } label: {
            if manager.isScanning {
                Label("停止", systemImage: "stop.fill")
            } else {
                Label("掃描", systemImage: "magnifyingglass")
            }
        }
        .disabled(manager.bluetoothState != .poweredOn)
    }
}

#Preview {
    ContentView()
}
