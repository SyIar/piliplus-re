import SwiftUI
import ChunUI
import Translation

struct PiliLiveChatView: View {
    @ObservedObject var viewModel: LiveRoomViewModel
    @ObservedObject var store: PiliLiveChatStore
    @PiliDismiss private var dismiss
    @State private var composer = false
    @State private var report: DanmakuItem?
    @State private var identity: PiliAccountIdentity?
    @State private var error: String?
    @State private var translated = ""
    @State private var translates = false
    @State private var liked = false
    @State private var liking = false
    var body: some View {
        NavigationStack {
            PiliList {
                Section {
                    NavigationLink { PiliLiveShieldView(api: viewModel.api, roomID: viewModel.roomID, store: store) } label: { PiliLabel("弹幕屏蔽规则", systemImage: "line.3.horizontal.decrease") }
                    NavigationLink { PiliLiveRankView(api: viewModel.api, roomID: viewModel.roomID, ownerID: viewModel.anchorOwner.mid) } label: { PiliLabel("贡献榜", systemImage: "chart.bar") }
                    PiliIconButton(liked ? "已点赞" : "为直播点赞", systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup") { like() }.disabled(liking)
                }
                if let error { Text(error).foregroundStyle(Color.cc.destructive) }
                Section("最近聊天") {
                    if store.messages.isEmpty { Text("等待直播弹幕…").foregroundStyle(.secondary) }
                    ForEach(store.messages.reversed()) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(item.senderName ?? "观众").font(.cc.base.bold())
                                if let meta = item.liveMetadata, !meta.medal.isEmpty { Text("\(meta.medal) \(meta.medalLevel)").piliFont(.sm).foregroundStyle(.secondary) }
                            }
                            if let meta = item.liveMetadata, meta.replyUID > 0 { Text("回复 @\(meta.replyName)").piliFont(.sm).foregroundStyle(.secondary) }
                            Text(item.text).piliFont(.base).textSelection(.enabled)
                        }.contextMenu { actions(item) }
                    }
                }
            }.navigationTitle("直播聊天").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { PiliIconButton("发弹幕", systemImage: "square.and.pencil") { composer = true } }
                }
                .onAppear { viewModel.isLiveChatOpen = true; viewModel.resumeLiveDanmakuIfNeeded() }
                .onDisappear { viewModel.isLiveChatOpen = false; if !viewModel.isDanmakuEnabled && viewModel.superChatStore.mode == 0 { viewModel.stopLiveDanmaku(clearItems: false) } }
                .task { identity = .init(viewModel.api.requestSnapshot()); store.load(roomID: viewModel.roomID, api: viewModel.api) }
                .piliSheet(isPresented: $composer) { PiliLiveComposer(viewModel: viewModel) }
                .piliSheet(item: $report) { PiliLiveReportView(api: viewModel.api, roomID: viewModel.roomID, item: $0) }
                .translationPresentation(isPresented: $translates, text: translated)
                .videoDestinations()
        }
    }
    @ViewBuilder private func actions(_ item: DanmakuItem) -> some View {
        PiliIconButton("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.text }
        PiliIconButton("翻译", systemImage: "translate") { translated = item.text; translates = true }
        if let meta = item.liveMetadata, meta.uid > 0 {
            NavigationLink(value: VideoOwner(mid: meta.uid, name: item.senderName ?? "观众", face: nil)) { PiliLabel("个人主页", systemImage: "person.crop.circle") }
            if !meta.id.isEmpty { PiliIconButton("回复", systemImage: "arrowshape.turn.up.left") { viewModel.liveReplyTarget = item; composer = true } }
            PiliIconButton("屏蔽用户", systemImage: "person.slash") {
                guard let identity else { return }
                Task {
                    do {
                        try await viewModel.api.piliLiveShieldUser(uid: meta.uid, remove: false, roomID: viewModel.roomID, identity: identity)
                        guard identity.matches(viewModel.api.requestSnapshot()) else { throw CancellationError() }
                        store.load(roomID: viewModel.roomID, api: viewModel.api, force: true)
                    } catch { self.error = error.localizedDescription }
                }
            }
            if meta.canReport { PiliIconButton("举报弹幕", systemImage: "exclamationmark.bubble") { report = item } }
        }
    }
    private func like() {
        guard !liking else { return }; liking = true
        let identity = PiliAccountIdentity(viewModel.api.requestSnapshot(purpose: .interaction))
        Task {
            defer { liking = false }
            do {
                try await viewModel.api.piliLikeLive(roomID: viewModel.roomID, ownerID: viewModel.anchorOwner.mid, identity: identity)
                guard identity.matches(viewModel.api.requestSnapshot(purpose: .interaction)) else { return }
                liked = true
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct PiliLiveReportView: View {
    let api: BiliAPIClient
    let roomID: Int
    let item: DanmakuItem
    @PiliDismiss private var dismiss
    @State private var identity: PiliAccountIdentity?
    @State private var reasonID = 1
    private let reasons = [(1, "违法违规"), (2, "低俗色情"), (3, "垃圾广告"), (4, "辱骂引战"), (5, "政治敏感"), (6, "青少年不良信息"), (0, "其他")]
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            PiliForm {
                Text(item.text)
                Picker("举报原因", selection: $reasonID) { ForEach(reasons, id: \.0) { Text($0.1).tag($0.0) } }
                if let error { Text(error).foregroundStyle(Color.cc.destructive) }
                Button("提交举报") {
                    guard let identity else { return }; busy = true
                    Task {
                        defer { busy = false }
                        do { try await api.piliReportLiveMessage(item, roomID: roomID, reason: reasons.first(where: { $0.0 == reasonID })?.1 ?? "其他", reasonID: reasonID, identity: identity); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(busy)
            }.navigationTitle("举报弹幕").task { if identity == nil { identity = .init(api.requestSnapshot()) } }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) } }
        }.piliInteractiveDismissDisabled(busy)
    }
}

struct PiliLiveShieldView: View {
    let api: BiliAPIClient
    let roomID: Int
    @ObservedObject var store: PiliLiveChatStore
    @State private var identity: PiliAccountIdentity?
    @State private var word = ""
    @State private var uid = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        PiliForm {
            if store.loading { ProgressView("加载屏蔽规则") }
            if let message = error ?? store.error { Text(message).foregroundStyle(Color.cc.destructive); Button("刷新") { store.load(roomID: roomID, api: api, force: true) } }
            Section("关键词") {
                HStack { TextField("屏蔽词", text: $word); Button("添加") { change { identity in try await api.piliLiveShieldKeyword(word, remove: false, roomID: roomID, identity: identity) } }.disabled(word.isEmpty) }
                ForEach(store.shield.keywords, id: \.self) { value in
                    HStack { Text(value); Spacer(); Button("删除", role: .destructive) { change { identity in try await api.piliLiveShieldKeyword(value, remove: true, roomID: roomID, identity: identity) } } }
                }
            }
            Section("用户") {
                HStack { TextField("UID", text: $uid).keyboardType(.numberPad); Button("屏蔽") { change { identity in try await api.piliLiveShieldUser(uid: Int(uid) ?? 0, remove: false, roomID: roomID, identity: identity) } }.disabled(Int(uid) == nil) }
                ForEach(store.shield.users, id: \.mid) { owner in
                    HStack { Text(owner.name.isEmpty ? String(owner.mid) : owner.name); Spacer(); Button("解除", role: .destructive) { change { identity in try await api.piliLiveShieldUser(uid: owner.mid, remove: true, roomID: roomID, identity: identity) } } }
                }
            }
        }.disabled(busy).navigationTitle("直播弹幕屏蔽")
            .task { identity = .init(api.requestSnapshot()); store.load(roomID: roomID, api: api, force: true) }
    }
    private func change(_ operation: @escaping (PiliAccountIdentity) async throws -> Void) {
        guard !busy, let identity else { return }; busy = true
        Task {
            defer { busy = false }
            do {
                try await operation(identity)
                guard identity.matches(api.requestSnapshot()) else { throw CancellationError() }
                word = ""; uid = ""; error = nil; store.load(roomID: roomID, api: api, force: true)
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct PiliLiveRankView: View {
    let api: BiliAPIClient
    let roomID: Int
    let ownerID: Int
    @State private var type = "online_rank"
    @State private var values: [DynamicJSONValue] = []
    @State private var page = 1
    @State private var more = false
    @State private var loading = false
    @State private var error: String?
    @State private var token = UUID()
    private let choices = [("online_rank", "在线"), ("daily_rank", "日榜"), ("weekly_rank", "周榜"), ("monthly_rank", "月榜")]
    var body: some View {
        PiliList {
            Picker("贡献榜", selection: $type) { ForEach(choices, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.segmented)
            if let error { Text(error); Button("重试") { Task { await load(reset: values.isEmpty) } } }
            ForEach(values, id: \.self) { value in
                NavigationLink(value: VideoOwner(mid: value["uid"].piliInt, name: value["name"].piliString, face: value["face"].piliString)) {
                    HStack { Text(value["name"].piliString); Spacer(); Text(value["score"].piliString).foregroundStyle(.secondary) }
                }
            }
            if loading { ProgressView() } else if more { Button("加载更多") { Task { await load(reset: false) } } }
            else if values.isEmpty && error == nil { Text("暂无榜单数据").foregroundStyle(.secondary) }
        }.navigationTitle("直播贡献榜").task(id: type) { await load(reset: true) }
    }
    private func load(reset: Bool) async {
        if reset { token = UUID(); values = []; page = 1 }
        else if loading { return }
        let id = token, scope = type; loading = true; error = nil
        defer { if token == id { loading = false } }
        do {
            let results = try await api.piliLiveRanks(roomID: roomID, ownerID: ownerID, type: scope, page: page)
            guard !Task.isCancelled, id == token else { return }
            var seen = Set(values.map { $0["uid"].piliInt })
            let unique = results.filter { $0["uid"].piliInt > 0 && seen.insert($0["uid"].piliInt).inserted }
            values.append(contentsOf: unique); more = results.count >= 100 && !unique.isEmpty; page += 1
        } catch { if id == token, !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
