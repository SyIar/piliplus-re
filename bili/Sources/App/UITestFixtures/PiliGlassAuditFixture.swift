import ChunUI
import SwiftUI

/// Deterministic coverage of the production page, selection and presentation adapters.
struct PiliGlassAuditFixture: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var route: Route?
    @State private var target: String?
    @State private var deleted = 0
    @State private var selected = Set<String>()

    private struct Route: Identifiable { let id: Int }

    var body: some View {
        NavigationStack {
            PiliForm {
                Section("设置") {
                    NavigationLink("界面设置") { MineInterfaceSettingsView(libraryStore: library) }
                        .accessibilityIdentifier("glass.settings")
                    NavigationLink("内容过滤") { MineContentFilterSettingsView(libraryStore: library) }
                    NavigationLink("多选列表") {
                        PiliSelectionList(selection: $selected) {
                            ForEach(["下载一", "下载二"], id: \.self) { value in Text(value).tag(value) }
                        }
                        .environment(\.editMode, .constant(.active))
                        .navigationTitle("已选择 \(selected.count) 项")
                    }
                }
                Section("弹层交互") {
                    Button("打开播放设置") { route = Route(id: 1) }
                        .accessibilityIdentifier("glass.open")
                    Button("删除测试条目", role: .destructive) { target = "测试条目" }
                        .accessibilityIdentifier("glass.delete")
                    Text("已删除 \(deleted) 次").accessibilityIdentifier("glass.deleted")
                }
                Section("文字与状态") {
                    Text("液态玻璃界面").piliFont(.lgBold)
                    Text("使用 ChunUI 的语义颜色与三档字体；较大的文字应能完整换行。")
                    PiliLabel("连接正常", systemImage: "checkmark.circle")
                        .foregroundStyle(Color.cc.success)
                    Text("无法连接时可以重试").piliFont(.sm).foregroundStyle(Color.cc.mutedForeground)
                }
            }
            .navigationTitle("界面预览")
            .navigationBarTitleDisplayMode(.inline)
        }
        .piliSheet(item: $route) { value in
            PiliGlassAuditSheet(number: value.id, replace: { route = Route(id: value.id + 1) })
        }
        .piliConfirmation("删除条目？", isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } })) {
            PiliAlertButton("确认删除", role: .destructive) {
                if target == "测试条目" { deleted += 1 }
            }
            PiliAlertButton("取消", role: .cancel)
        } message: { "删除后无法恢复。" }
        .onChange(of: library.appTintColorHex, initial: true) { _, _ in
            PiliChunUIBridge.configure(tint: library.appTintColor)
        }
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--glass-preview-purple") {
                library.setAppTintColorHex("#AF52DE")
            } else if arguments.contains("--glass-preview-default") {
                library.resetAppTintColor()
            }
            guard arguments.contains("--glass-preview-sheet") || arguments.contains("--glass-preview-alert") else { return }
            try? await Task.sleep(for: .milliseconds(600))
            if arguments.contains("--glass-preview-sheet") { route = Route(id: 1) }
            else { target = "测试条目" }
        }
    }
}

private struct PiliGlassAuditSheet: View {
    let number: Int
    let replace: () -> Void
    @PiliDismiss private var dismiss
    @State private var nested = false
    @State private var busy = false
    @State private var enabled = true
    @State private var note = ""
    @State private var detent = PiliSheetDetent.medium
    var body: some View {
        NavigationStack {
            PiliForm {
                Section("播放偏好") {
                    Toggle("自动连播", isOn: $enabled)
                    Button("展开面板") { detent = .large }.accessibilityIdentifier("glass.expand")
                    Button("打开内层面板") { nested = true }.accessibilityIdentifier("glass.nested")
                    Button("切换到下一面板", action: replace).accessibilityIdentifier("glass.replace")
                    Button(busy ? "结束提交" : "模拟提交") { busy.toggle() }.accessibilityIdentifier("glass.busy")
                    Text(busy ? "提交期间禁止下拉关闭" : "可以下拉关闭")
                    TextField("备注", text: $note)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("glass.note")
                }
            }
            .navigationTitle("播放设置 \(number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.disabled(busy).accessibilityIdentifier("glass.close")
                }
            }
        }
        .piliPresentationDetents([.medium, .large], selection: $detent)
        .piliInteractiveDismissDisabled(busy)
        .piliSheet(isPresented: $nested) { PiliGlassAuditNestedSheet() }
    }
}

private struct PiliGlassAuditNestedSheet: View {
    @PiliDismiss private var dismiss
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        NavigationStack {
            PiliForm {
                Text("内层面板").accessibilityIdentifier("glass.inner.title")
                Text(library.danmakuEnabled ? "弹幕已开启" : "弹幕已关闭")
                Button("关闭内层") { dismiss() }.accessibilityIdentifier("glass.inner.close")
            }
            .navigationTitle("更多设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Exercises the production card and menus without a feed request or playback.
struct PiliGlassFeedFixture: View {
    @State private var opened = 0
    @State private var prewarmed = 0
    @State private var ownerOpened = false
    private let videos = [
        VideoItem(bvid: "BV1fixture001", aid: nil, title: "旅行影像：山川与城市", pic: nil, desc: nil,
                  duration: 180, pubdate: nil, owner: .init(mid: 123, name: "示例 UP 主", face: nil),
                  stat: nil, cid: nil, pages: nil, dimension: nil),
        VideoItem(bvid: "BV1fixture002", aid: nil, title: "音乐现场与幕后故事", pic: nil, desc: nil,
                  duration: 240, pubdate: nil, owner: .init(mid: 456, name: "音乐频道", face: nil),
                  stat: nil, cid: nil, pages: nil, dimension: nil)
    ]

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let metrics = HomeFeedLayoutMetrics(mode: .doubleColumn, containerWidth: geometry.size.width)
                ScrollView {
                    LazyVGrid(columns: metrics.doubleColumns, spacing: 16) {
                        ForEach(videos) { video in
                            HomeFeedVideoCardButton(metrics: metrics, video: video, display: .init(video: video),
                                actions: .init(onVideoSelect: nil, onVideoTap: { _ in opened += 1 },
                                               onVideoPress: { _ in prewarmed += 1 }, onCardAppear: { _, _ in },
                                               onCardDisappear: { _ in }, onLoadMore: { _ in }, onRefreshFromLastSeenMarker: {}))
                        }
                    }.padding(12)
                    Text("播放 \(opened) · 预热 \(prewarmed)").accessibilityIdentifier("glass.feed.activity")
                    if ownerOpened { Text("已打开 UP 主").accessibilityIdentifier("glass.feed.owner") }
                }
            }
            .navigationTitle("推荐")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.openVideoOwnerRouteAction, { _ in ownerOpened = true })
    }
}
