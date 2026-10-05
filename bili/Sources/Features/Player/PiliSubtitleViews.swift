import ChunUI
import PiliPlaybackCore
import SwiftUI
import UniformTypeIdentifiers

struct PiliSubtitleOverlay: View {
    @ObservedObject var controller: PiliSubtitleController
    @ObservedObject var clock: PlayerPlaybackClock
    var landscape = false
    @AppStorage("piliplus.subtitle.fontSize") private var fontSize = 17.0
    @AppStorage("piliplus.subtitle.landscapeSize") private var landscapeSize = 23.0
    @AppStorage("piliplus.subtitle.bottom") private var bottom = 54.0
    @AppStorage("piliplus.subtitle.opacity") private var opacity = 0.65
    @AppStorage("piliplus.subtitle.delay") private var delay = 0.0
    @AppStorage("piliplus.subtitle.bold") private var bold = true
    var body: some View {
        let text = controller.timeline.active(at: clock.currentTime - delay).map(\.content).joined(separator: "\n")
        VStack {
            Spacer(minLength: 0)
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: landscape ? landscapeSize : fontSize, weight: bold ? .semibold : .regular))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black, radius: 1, x: 0, y: 1)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.black.opacity(opacity), in: RoundedRectangle(cornerRadius: 4))
                    .padding(.horizontal, 16)
                    .padding(.bottom, bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

struct PiliOnlineSubtitleLayer: View {
    let controller: PiliSubtitleController
    let api: BiliAPIClient
    let video: VideoItem
    let cid: Int?
    let clock: PlayerPlaybackClock
    let landscape: Bool
    var body: some View {
        PiliSubtitleOverlay(controller: controller, clock: clock, landscape: landscape)
            .task(id: "\(video.bvid):\(cid ?? 0):\(api.requestSnapshot(purpose: .playback).playbackCredentialVersion)") {
                guard let cid, cid > 0 else { return }
                await controller.load(video: video, cid: cid, api: api)
            }
    }
}

struct PiliSubtitleSettingsView: View {
    @ObservedObject var controller: PiliSubtitleController
    var seek: ((Double) -> Void)?
    @State private var importsFile = false
    @State private var exportURL: URL?
    @State private var message: String?
    @AppStorage("piliplus.subtitle.mode") private var mode = "withoutAI"
    @AppStorage("piliplus.subtitle.fontSize") private var fontSize = 17.0
    @AppStorage("piliplus.subtitle.landscapeSize") private var landscapeSize = 23.0
    @AppStorage("piliplus.subtitle.bottom") private var bottom = 54.0
    @AppStorage("piliplus.subtitle.opacity") private var opacity = 0.65
    @AppStorage("piliplus.subtitle.delay") private var delay = 0.0
    @AppStorage("piliplus.subtitle.bold") private var bold = true
    var body: some View {
        NavigationStack {
            List {
                Section("字幕语言") {
                    if controller.isLoading { ProgressView("加载字幕") }
                    if let error = controller.errorMessage { Text(error).ccText(font: .cc.sm, color: .cc.mutedForeground) }
                    Button("关闭字幕") { controller.select(nil) }
                    ForEach(controller.tracks) { track in
                        Button { controller.select(track.id) } label: {
                            HStack {
                                Text(track.title).ccText(font: .cc.base, color: .cc.foreground)
                                Spacer()
                                if controller.selectedID == track.id { Text("已选择").ccText(font: .cc.sm, color: .cc.primary) }
                            }
                        }
                    }
                    if controller.tracks.isEmpty && !controller.isLoading { Text("暂无在线字幕，可导入本地 SRT 或 VTT 文件").ccText(font: .cc.sm, color: .cc.mutedForeground) }
                    Picker("后续视频默认字幕", selection: $mode) {
                        Text("关闭").tag("off")
                        Text("开启").tag("on")
                        Text("仅非 AI 字幕").tag("withoutAI")
                    }.onChange(of: mode) { _, _ in controller.selectPreferred() }
                }
                Section("显示") {
                    Stepper("竖屏字号 \(Int(fontSize))", value: $fontSize, in: 10...40)
                    Stepper("全屏字号 \(Int(landscapeSize))", value: $landscapeSize, in: 12...60)
                    Toggle("加粗", isOn: $bold)
                    VStack(alignment: .leading) { Text("底部间距 \(Int(bottom))"); Slider(value: $bottom, in: 0...150, step: 2) }
                    VStack(alignment: .leading) { Text("背景不透明度 \(Int(opacity * 100))%"); Slider(value: $opacity, in: 0...1, step: 0.05) }
                    Stepper("字幕延迟 \(delay, specifier: "%.1f") 秒", value: $delay, in: -30...30, step: 0.1)
                }
                Section("字幕文件") {
                    CCNeoButton("导入 SRT / VTT", variant: .secondary, icon: PikaIcon.Name.filePlus) { importsFile = true }
                    HStack {
                        CCNeoButton("导出 SRT", variant: .ghost, disabled: controller.timeline.cues.isEmpty) { export(vtt: false) }
                        CCNeoButton("导出 VTT", variant: .ghost, disabled: controller.timeline.cues.isEmpty) { export(vtt: true) }
                    }
                    if let exportURL { ShareLink("分享字幕文件", item: exportURL) }
                    if let message { Text(message).ccText(font: .cc.sm, color: .cc.mutedForeground) }
                }
                if let seek, !controller.timeline.cues.isEmpty {
                    Section("字幕列表 · 点击跳转") {
                        ForEach(Array(controller.timeline.cues.enumerated()), id: \.offset) { _, cue in
                            Button {
                                seek(max(0, cue.from + delay))
                                AppHelper.shared.dismissSheet()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(Int(cue.from) / 60):\(String(format: "%02d", Int(cue.from) % 60))").ccText(font: .cc.sm, color: .cc.mutedForeground)
                                    Text(cue.content).ccText(font: .cc.base, color: .cc.foreground)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("字幕")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { AppHelper.shared.dismissSheet() } label: { PikaIcon(PikaIcon.Name.close) }.accessibilityLabel("关闭")
                }
            }
        }
        .fileImporter(isPresented: $importsFile, allowedContentTypes: [.plainText, UTType(filenameExtension: "srt") ?? .text, UTType(filenameExtension: "vtt") ?? .text]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 8 * 1024 * 1024 else { throw PiliOfflineError.message("字幕文件不能超过 8 MB") }
                let text = try String(contentsOf: url, encoding: .utf8)
                try controller.importText(text, name: url.deletingPathExtension().lastPathComponent)
                message = nil
            } catch { message = error.localizedDescription }
        }
    }
    private func export(vtt: Bool) {
        do { exportURL = try controller.export(vtt: vtt); message = nil }
        catch { message = error.localizedDescription }
    }
    static func present(controller: PiliSubtitleController, seek: ((Double) -> Void)? = nil) {
        AppHelper.shared.presentSheet(.sheet) { Self(controller: controller, seek: seek) }
    }
}
