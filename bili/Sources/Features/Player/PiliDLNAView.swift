import ChunUI
import PiliPlaybackCore
import SwiftUI

struct PiliDLNAView: View {
    var source: (() throws -> PiliCastSource)? = nil
    @StateObject private var discovery = PiliDLNADiscovery()
    @ObservedObject private var casting = PiliDLNAController.shared
    @State private var manualAddress = ""
    @State private var seekValue: Double = 0
    @State private var volumeValue: Double = 50
    @State private var isSeeking = false
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Form {
                if let device = casting.renderer {
                    Section("正在投屏 · \(device.name)") {
                        Text(casting.title).ccText(font: .cc.baseBold, color: .cc.foreground)
                        if casting.duration > 0 {
                            Slider(value: $seekValue, in: 0...max(1, casting.duration), onEditingChanged: { editing in
                                isSeeking = editing
                                if !editing { casting.seek(seekValue) }
                            }).disabled(casting.isBusy)
                            Text("\(UPnPSOAP.timestamp(isSeeking ? seekValue : casting.position)) / \(UPnPSOAP.timestamp(casting.duration))")
                                .monospacedDigit().ccText(font: .cc.sm, color: .cc.mutedForeground)
                        }
                        HStack {
                            Button(casting.isPlaying ? "暂停" : "播放") { casting.playPause() }.buttonStyle(.glass)
                            Spacer()
                            Button("停止投屏", role: .destructive) { casting.stop() }.buttonStyle(.glass)
                        }.disabled(casting.isBusy)
                        if device.rendering != nil {
                            Text("电视音量 \(Int(volumeValue))").ccText(font: .cc.sm, color: .cc.mutedForeground)
                            Slider(value: $volumeValue, in: 0...100, step: 1, onEditingChanged: { if !$0 { casting.setVolume(volumeValue) } })
                                .disabled(casting.isBusy)
                        }
                        Button("定时停止") { PiliPlaybackToolsView.present() }
                    }
                    if let queue = casting.queue, !queue.entries.isEmpty {
                        Section("投屏列表") {
                            HStack {
                                Button("上一条") { casting.selectQueueItem(casting.queueIndex - 1) }.disabled(casting.queueIndex == 0)
                                Spacer()
                                Button("下一条") { casting.selectQueueItem(casting.queueIndex + 1) }.disabled(casting.queueIndex + 1 >= queue.entries.count)
                            }
                            ForEach(Array(queue.entries.enumerated()), id: \.element.id) { index, entry in
                                Button { casting.selectQueueItem(index) } label: {
                                    HStack { Text(entry.title); Spacer(); if index == casting.queueIndex { Image(systemName: "tv.fill") } }
                                }
                            }
                        }.disabled(casting.isBusy)
                    }
                }
                if source == nil, casting.renderer == nil, !casting.isBusy {
                    Section { Text("暂无正在播放的投屏，请在视频播放页或离线播放器中选择投屏。") }
                }
                if casting.isBusy { Section { ProgressView("正在连接设备") } }
                if let message = localError ?? casting.errorMessage ?? discovery.errorMessage {
                    Section { Text(message).ccText(font: .cc.sm, color: .cc.destructive) }
                }
                if source != nil {
                    Section("选择设备") {
                        ForEach(discovery.devices) { device in
                            Button { start(device) } label: {
                                HStack {
                                    Image(systemName: "tv")
                                    Text(device.name)
                                    Spacer()
                                    if casting.renderer?.id == device.id { Image(systemName: "checkmark") }
                                }
                            }.disabled(casting.isBusy)
                        }
                        if discovery.devices.isEmpty {
                            Text(discovery.isSearching ? "正在搜索同一 Wi-Fi 下的电视…" : "未发现设备，请开启电视的 DLNA 功能后重新搜索，或手动添加。")
                                .ccText(font: .cc.sm, color: .cc.mutedForeground)
                        }
                        Button(discovery.isSearching ? "搜索中…" : "搜索设备") { discovery.search() }
                            .disabled(discovery.isSearching)
                    }
                    Section("手动添加设备") {
                        TextField("http://192.168.1.10:端口/description.xml", text: $manualAddress)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("读取设备信息") { discovery.add(manualAddress) }.disabled(manualAddress.isEmpty)
                    }
                }
                Section {
                    Text("投屏时请保持此 App 在前台，并与电视连接同一 Wi-Fi。在线播放需要电视支持 HLS；若不兼容，可下载视频后投屏。清晰度和编码取当前播放选项，H.264 的设备兼容性通常更好。")
                        .ccText(font: .cc.sm, color: .cc.mutedForeground)
                }
            }
            .tint(.cc.primary)
            .navigationTitle("DLNA 投屏")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { AppHelper.shared.dismissSheet() } } }
            .onAppear { seekValue = casting.position; volumeValue = casting.volume; if source != nil { discovery.search() } }
            .onDisappear { discovery.stop() }
            .onChange(of: casting.position) { _, value in if !isSeeking { seekValue = value } }
            .onChange(of: casting.volume) { _, value in volumeValue = value }
        }
    }
    private func start(_ device: UPnPRenderer) {
        do { if let value = try source?() { localError = nil; casting.start(value, on: device) } }
        catch { localError = error.localizedDescription }
    }
}
