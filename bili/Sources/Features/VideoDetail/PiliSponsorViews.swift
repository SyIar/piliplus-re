import SwiftUI
import ChunUI

struct PiliSponsorSettingsView: View {
    @ObservedObject private var preferences = PiliSponsorPreferences.shared
    var body: some View {
        PiliList {
            Section {
                Text("自动：按片段动作跳过或临时静音。手动：显示操作按钮。忽略：不处理此分类。整个视频标记和精彩时刻可在片段列表查看，不会自动跳过整部视频。")
                    .font(.cc.sm).foregroundStyle(.secondary)
            }
            ForEach(PiliSponsorCategory.allCases) { category in
                Picker(category.title, selection: Binding(get: { preferences.mode(category.rawValue) }, set: { preferences.set($0, category: category.rawValue) })) {
                    ForEach(PiliSponsorMode.allCases) { Text($0.title).tag($0) }
                }
            }
        }.navigationTitle("空降分类策略").task { preferences.reload() }
    }
}

struct PiliSponsorManualPrompt: View {
    @ObservedObject var player: PlayerStateViewModel
    @ObservedObject private var preferences = PiliSponsorPreferences.shared
    var body: some View {
        if let segment = player.activeSponsorBlockSegment, preferences.mode(segment.category) == .manual {
            VStack {
                Spacer()
                HStack {
                    PiliIconButton("\(segment.actionType == "mute" ? "静音" : "跳过") · \(segment.title)", systemImage: segment.actionType == "mute" ? "speaker.slash" : "forward.end") {
                        if segment.actionType == "mute" { player.manuallyMuteSponsorBlockSegment(segment) }
                        else { player.manuallySkipSponsorBlockSegment(segment) }
                    }.buttonStyle(.glass)
                    Spacer()
                }.padding(.leading, 18).padding(.bottom, 105)
            }
        }
    }
}

struct PiliSponsorView: View {
    let model: VideoDetailViewModel
    @State private var segments: [SponsorBlockSegment] = []
    @State private var loading = false
    @State private var busy = false
    @State private var message: String?
    @State private var start = 0.0
    @State private var end = 0.0
    @State private var category: PiliSponsorCategory = .sponsor
    @State private var action = "skip"
    @State private var confirmsSubmit = false
    @PiliDismiss private var dismiss
    private var duration: Double { model.stablePlayerViewModel?.duration ?? Double(model.detail.duration ?? 0) }
    private var valid: Bool { duration > 0 && start >= 0 && end <= duration && (end > start || action == "poi" && start == end) && category.actions.contains(action) }
    var body: some View {
        NavigationStack {
            PiliList {
                Section { NavigationLink { PiliSponsorSettingsView() } label: { PiliLabel("分类处理策略", systemImage: "slider.horizontal.3") } }
                if let message { Text(message).foregroundStyle(.secondary) }
                if loading { ProgressView("加载空降片段") }
                Section("片段") {
                    if !loading && segments.isEmpty { Text("暂无空降片段") }
                    ForEach(segments) { segment in segmentRow(segment) }
                    Button("刷新") { Task { await load() } }
                }
                Section("提交片段") {
                    Picker("分类", selection: $category) { ForEach(PiliSponsorCategory.allCases) { Text($0.title).tag($0) } }
                        .onChange(of: category) { _, value in action = value.actions[0] }
                    Picker("动作", selection: $action) { ForEach(category.actions, id: \.self) { Text(actionTitle($0)).tag($0) } }
                    HStack { Text("开始（秒）"); TextField("开始", value: $start, format: .number).keyboardType(.decimalPad); Button("取当前时间") { start = model.stablePlayerViewModel?.currentTime ?? 0 } }
                    HStack { Text("结束（秒）"); TextField("结束", value: $end, format: .number).keyboardType(.decimalPad); Button("取当前时间") { end = model.stablePlayerViewModel?.currentTime ?? 0 } }
                    if action == "full" { Button("标记整个视频") { start = 0; end = duration } }
                    if action == "poi" { Button("设为当前精彩时刻") { start = model.stablePlayerViewModel?.currentTime ?? 0; end = start } }
                    Button("提交到空降社区") { confirmsSubmit = true }.disabled(!valid || busy)
                    Text("提交内容会公开到空降社区。请先核对时间和分类；社区身份独立于 B 站账号，保存在钥匙串中。").font(.cc.sm).foregroundStyle(.secondary)
                }
            }.disabled(busy).navigationTitle("空降助手").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(busy) } }
                .task { await load() }
                .piliConfirmation("将此片段公开提交到空降社区？", isPresented: $confirmsSubmit, titleVisibility: .visible) {
                    PiliAlertButton("确认提交") { submit() }
                } message: { "\(category.title) · \(actionTitle(action)) · \(start.formatted())–\(end.formatted()) 秒" }
        }.piliInteractiveDismissDisabled(busy)
    }
    private func segmentRow(_ segment: SponsorBlockSegment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PiliSponsorCategory(rawValue: segment.category)?.title ?? segment.title).font(.cc.baseBold)
            Text("\(BiliFormatters.duration(Int(segment.startTime)))–\(BiliFormatters.duration(Int(segment.endTime))) · \(actionTitle(segment.actionType))").font(.cc.sm)
            HStack {
                Button("预览") { model.stablePlayerViewModel?.previewSponsorBlockSegment(segment) }
                Button("跳转") { model.stablePlayerViewModel?.manuallySkipSponsorBlockSegment(segment) }
                PiliIconButton("赞成", systemImage: "hand.thumbsup") { vote(segment, type: 1) }
                PiliIconButton("反对", systemImage: "hand.thumbsdown") { vote(segment, type: 0) }
            }.buttonStyle(.borderless).font(.cc.sm)
            Menu("修改分类") { ForEach(PiliSponsorCategory.allCases.filter { $0.actions.contains(segment.actionType) }) { category in
                Button(category.title) { change { try await model.sponsorBlockService.vote(uuid: segment.uuid, category: category.rawValue, userID: $0) } }
            } }.font(.cc.sm)
        }
    }
    private func actionTitle(_ value: String) -> String { ["skip": "跳过", "mute": "静音", "full": "整个视频标记", "poi": "精彩时刻"][value] ?? value }
    private func vote(_ segment: SponsorBlockSegment, type: Int) { change { try await model.sponsorBlockService.vote(uuid: segment.uuid, type: type, userID: $0) } }
    private func submit() {
        guard valid, let cid = model.selectedCID else { return }
        let bvid = model.detail.bvid, total = duration, begin = start, finish = end
        let selectedCategory = category, selectedAction = action
        change { userID in try await model.sponsorBlockService.submit(bvid: bvid, cid: cid, duration: total, start: begin, end: finish, category: selectedCategory, action: selectedAction, userID: userID) }
    }
    private func change(_ operation: @escaping (String) async throws -> Void) {
        guard !busy else { return }; busy = true; message = nil
        Task {
            defer { busy = false }
            do { try await operation(PiliSponsorIdentity.readOrCreate()); message = "社区已接收"; await load() }
            catch { message = error.localizedDescription }
        }
    }
    private func load() async {
        guard !loading, let cid = model.selectedCID else { return }; loading = true
        let bvid = model.detail.bvid
        defer { loading = false }
        do {
            let values = try await model.sponsorBlockService.fetchSkipSegments(bvid: bvid, cid: cid)
            guard !Task.isCancelled, model.selectedCID == cid, model.detail.bvid == bvid else { return }
            segments = values; model.sponsorBlockSegments = values; model.applySponsorBlockSegmentsToPlayer()
        } catch { if !Task.isCancelled { message = error.localizedDescription } }
    }
}
