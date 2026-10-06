import SwiftUI

struct PiliCollectedContentView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var kind = PiliCollectedKind.anime
    @State private var status = 0
    @State private var items: [DynamicJSONValue] = []
    @State private var page = 1
    @State private var more = true
    @State private var busy = false
    @State private var mutating = false
    @State private var error: String?
    @State private var identity: PiliAccountIdentity?
    @State private var generation = UUID()
    @State private var selected = Set<Int>()
    @State private var deleting: DynamicJSONValue?
    var body: some View {
        List {
            Picker("内容类型", selection: $kind) { ForEach(PiliCollectedKind.allCases) { Text($0.title).tag($0) } }.disabled(mutating)
            if kind.isPGC {
                Picker("追看状态", selection: $status) { Text("全部").tag(0); Text("想看").tag(1); Text("在看").tag(2); Text("看过").tag(3) }.disabled(mutating)
                HStack {
                    Button("选择已加载") { selected = Set(items.prefix(100).map { $0["season_id"].piliInt }.filter { $0 > 0 }) }
                    Menu("修改状态（\(selected.count)）") {
                        Button("想看") { updateStatus(1) }; Button("在看") { updateStatus(2) }; Button("看过") { updateStatus(3) }
                        Button("取消选择") { selected = [] }
                    }.disabled(selected.isEmpty)
                }.font(.caption).disabled(mutating)
            }
            ForEach(items, id: \.self) { item in
                HStack {
                    if kind.isPGC {
                        let id = item["season_id"].piliInt
                        Button { if selected.contains(id) { selected.remove(id) } else if selected.count < 100 { selected.insert(id) } } label: {
                            Image(systemName: selected.contains(id) ? "checkmark.circle.fill" : "circle")
                        }.buttonStyle(.borderless).accessibilityLabel("选择 \(item["title"].piliString)")
                    }
                    destination(item)
                }.disabled(mutating).contextMenu { Button("取消收藏或订阅", role: .destructive) { deleting = item } }
            }
            if busy || mutating { ProgressView() }
            else if let error { Text(error).foregroundStyle(.red); Button("重试") { Task { await load(reset: identity == nil) } } }
            else if more { Button("加载更多") { Task { await load() } } }
            else if items.isEmpty { Text("暂无收藏内容") }
        }.navigationTitle("追番与其他收藏")
            .task(id: sessionStore.playbackCredentialVersion) { identity = nil; await load(reset: true) }
            .onChange(of: kind) { Task { await load(reset: true) } }.onChange(of: status) { Task { await load(reset: true) } }
            .refreshable { await load(reset: true) }
            .confirmationDialog("确认取消这项收藏或订阅？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                if let item = deleting { Button("确认取消", role: .destructive) { remove(item) } }
            }
    }
    @ViewBuilder private func destination(_ item: DynamicJSONValue) -> some View {
        switch kind {
        case .anime, .cinema:
            if let media = try? item.piliDecode(SearchMediaItem.self) { SearchResultRouteRow(result: kind == .anime ? .bangumi(media) : .movie(media)) }
        case .articles:
            if let url = URL(string: "https://www.bilibili.com/opus/\(item["opus_id"].piliString)") {
                AppLinkButton(url: url) { Text(item["content"].piliString).lineLimit(4) }
            }
        case .topics:
            NavigationLink { PiliTopicView(api: dependencies.api, id: item["id"].piliInt, name: item["name"].piliString) } label: { Text(item["name"].piliString) }
        case .subscriptions:
            if let folder = try? item.piliDecode(FavoriteFolder.self) {
                NavigationLink { PiliPublicFavoriteView(api: dependencies.api, folder: folder, seasonID: item["type"].piliInt == 11 ? nil : folder.id) } label: {
                    VStack(alignment: .leading) { Text(folder.displayTitle); Text("\(folder.mediaCount ?? 0) 个内容").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
    private func load(reset: Bool = false) async {
        if reset { generation = UUID(); page = 1; items = []; selected = []; more = true }
        else if busy || !more { return }
        let ticket = generation; busy = true; error = nil; defer { if ticket == generation { busy = false } }
        do {
            let context = dependencies.api.requestSnapshot()
            if identity == nil { identity = .init(context) }
            guard let identity, identity.matches(context) else { throw BiliAPIError.missingSESSDATA }
            let result = try await dependencies.api.piliCollectedContent(kind, page: page, status: status, identity: identity)
            guard generation == ticket, !Task.isCancelled else { return }
            var seen = Set(items); let fresh = result.items.filter { seen.insert($0).inserted }
            items.append(contentsOf: fresh); more = result.more && !fresh.isEmpty; page += 1
        } catch { if generation == ticket, !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func remove(_ item: DynamicJSONValue) {
        guard let identity, !mutating else { return }; mutating = true
        let current = kind, ticket = generation
        Task {
            defer { mutating = false; deleting = nil }
            do {
                try await dependencies.api.piliCollectedRemove(current, item: item, identity: identity)
                if ticket == generation { items.removeAll { $0 == item }; selected.remove(item["season_id"].piliInt) }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func updateStatus(_ status: Int) {
        guard let identity, !mutating, !selected.isEmpty else { return }; mutating = true
        let ids = selected
        Task {
            defer { mutating = false }
            do { try await dependencies.api.piliFollowStatus(ids: ids, status: status, identity: identity); await load(reset: true) }
            catch { self.error = error.localizedDescription }
        }
    }
}
