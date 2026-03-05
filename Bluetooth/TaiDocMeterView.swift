//
//  TaiDocMeterView.swift
//  Bluetooth
//
//  Created by Edward Chang on 2026/03/05.
//

import SwiftUI
import CoreBluetooth

// MARK: - TaiDoc 儀器配對主頁面

struct TaiDocMeterView: View {
    @StateObject private var meterManager = TaiDocMeterManager()
    @State private var showSearchSheet = false
    @State private var showRenameAlert = false
    @State private var renamingMeter: PairedMeter?
    @State private var renameText = ""

    var body: some View {
        List {
            // 藍牙狀態
            Section {
                HStack {
                    Circle()
                        .fill(meterManager.bluetoothState == .poweredOn ? .green : .red)
                        .frame(width: 10, height: 10)
                    Text(meterManager.stateDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // 連線狀態
            if meterManager.connectionState != .idle {
                Section("連線狀態") {
                    HStack {
                        Text(meterManager.connectedMeterName ?? "")
                            .font(.headline)
                        Spacer()
                        if meterManager.connectionState == .ready {
                            Text(meterManager.connectionState.description)
                                .foregroundColor(.green)
                        } else {
                            ProgressView()
                                .padding(.trailing, 4)
                            Text(meterManager.connectionState.description)
                                .foregroundColor(.secondary)
                        }
                    }

                    if meterManager.connectionState.isActive {
                        Button("中斷連線", role: .destructive) {
                            meterManager.disconnect()
                        }
                    }
                }
            }

            // 已配對儀器列表
            Section {
                if meterManager.pairedMeters.isEmpty {
                    Text("尚無已配對儀器")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(meterManager.pairedMeters) { meter in
                        PairedMeterRow(
                            meter: meter,
                            isConnected: meterManager.connectedMeterName == meter.name
                                && meterManager.connectionState == .ready,
                            onConnect: {
                                meterManager.connectToMeter(meter)
                            },
                            onRename: {
                                renamingMeter = meter
                                renameText = meter.name
                                showRenameAlert = true
                            },
                            onDelete: {
                                meterManager.removePairedMeter(meter)
                            }
                        )
                    }
                }
            } header: {
                HStack {
                    Text("已配對儀器")
                    Spacer()
                    Text("\(meterManager.pairedMeters.count)/\(TaiDocMeterManager.maxPairedMeters)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // 監聽模式
            if !meterManager.pairedMeters.isEmpty && meterManager.connectionState == .idle {
                Section {
                    Button {
                        meterManager.listenForPairedMeters()
                    } label: {
                        Label("監聽已配對儀器", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .disabled(meterManager.bluetoothState != .poweredOn)
                } footer: {
                    Text("自動掃描並連線已配對清單中的儀器")
                }
            }

            // GATT Services（連線成功後顯示）
            if meterManager.connectionState == .ready {
                ForEach(meterManager.discoveredServices) { service in
                    Section(service.name + " (\(service.uuid.uuidString))") {
                        ForEach(service.characteristics) { characteristic in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(characteristic.name)
                                    .font(.subheadline)
                                Text(characteristic.uuid.uuidString)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(characteristic.propertiesDescription)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // 接收到的資料
                if !meterManager.receivedData.isEmpty {
                    Section("接收到的資料") {
                        ForEach(Array(meterManager.receivedData.enumerated()), id: \.offset) { index, data in
                            Text("[\(index)] \(data.hexString)")
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
        }
        .navigationTitle("TaiDoc 儀器")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSearchSheet = true
                } label: {
                    Label("搜尋", systemImage: "magnifyingglass")
                }
                .disabled(meterManager.bluetoothState != .poweredOn
                          || meterManager.connectionState.isActive)
            }
        }
        .sheet(isPresented: $showSearchSheet) {
            SearchMeterSheet(meterManager: meterManager)
        }
        .alert("重新命名儀器", isPresented: $showRenameAlert) {
            TextField("輸入新名稱", text: $renameText)
            Button("確定") {
                if let meter = renamingMeter, !renameText.isEmpty {
                    meterManager.renamePairedMeter(meter, to: renameText)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("錯誤", isPresented: .init(
            get: { meterManager.errorMessage != nil },
            set: { if !$0 { meterManager.errorMessage = nil } }
        )) {
            Button("確定", role: .cancel) {}
        } message: {
            Text(meterManager.errorMessage ?? "")
        }
    }
}

// MARK: - 已配對儀器列

struct PairedMeterRow: View {
    let meter: PairedMeter
    let isConnected: Bool
    let onConnect: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(meter.name)
                    .font(.headline)
                if meter.name != meter.originalName {
                    Text("原始名稱: \(meter.originalName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("UUID: \(meter.id.prefix(8))...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isConnected {
                onConnect()
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("刪除", systemImage: "trash")
            }

            Button {
                onRename()
            } label: {
                Label("重新命名", systemImage: "pencil")
            }
            .tint(.orange)
        }
    }
}

// MARK: - 搜尋儀器 Sheet

struct SearchMeterSheet: View {
    @ObservedObject var meterManager: TaiDocMeterManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                if meterManager.connectionState == .scanning {
                    HStack {
                        ProgressView()
                        Text("搜尋中... (\(Int(TaiDocMeterManager.scanDuration)) 秒)")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }

                if meterManager.discoveredMeters.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "sensor.tag.radiowaves.forward")
                            .font(.system(size: 50))
                            .foregroundColor(.blue.opacity(0.5))

                        if meterManager.connectionState == .scanning {
                            Text("正在搜尋 TaiDoc 儀器...")
                                .foregroundColor(.secondary)
                        } else {
                            Text("點擊下方按鈕開始搜尋")
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                } else {
                    List(meterManager.discoveredMeters) { meter in
                        Button {
                            meterManager.addToPaired(meter)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meter.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text("RSSI: \(meter.rssi) dBm")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                let alreadyPaired = meterManager.pairedMeters.contains {
                                    $0.id == meter.id.uuidString
                                }
                                if alreadyPaired {
                                    Text("已配對")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .disabled(meterManager.pairedMeters.contains {
                            $0.id == meter.id.uuidString
                        })
                    }
                }
            }
            .navigationTitle("搜尋 TaiDoc 儀器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") {
                        meterManager.stopScan()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if meterManager.connectionState == .scanning {
                        Button("停止") {
                            meterManager.stopScan()
                        }
                    } else {
                        Button("開始掃描") {
                            meterManager.startScan()
                        }
                    }
                }
            }
            .onAppear {
                meterManager.startScan()
            }
        }
    }
}

#Preview {
    NavigationStack {
        TaiDocMeterView()
    }
}
