import SwiftUI

extension BiliAPIClient {
    func piliFollowedLiveRooms(page: Int, identity: PiliAccountIdentity) async throws -> (rooms: [LiveRoom], more: Bool) {
        let data = try await piliContentRead("/xlive/web-ucenter/user/following", query: ["page": String(page), "page_size": "9", "ignoreRecord": "1", "hit_ab": "true"],
            identity: identity, base: Self.piliLiveBase, referer: "https://live.bilibili.com/")
        let rooms = data["list"].piliArray.compactMap { try? $0.piliDecode(LiveRoom.self) }.filter { $0.roomID > 0 && $0.isLive }
        return (rooms, page < data["totalPage"].piliInt)
    }
}

struct PiliLiveExploreView: View {
    let api: BiliAPIClient
    @State private var areas: [LiveAreaGroup] = []
    @State private var error: String?
    @State private var loading = false
    @State private var query = ""
    var body: some View {
        List {
            Section {
                NavigationLink { PiliLiveAreaRoomsView(api: api, title: "我关注的直播", parentID: nil, areaID: 0) } label: { Label("我关注的直播", systemImage: "heart") }
            }
            if loading { ProgressView() }
            if let error { Text(error); Button("重试") { Task { await load() } } }
            ForEach(areas) { group in
                Section(group.name) {
                    if query.isEmpty { NavigationLink("全部\(group.name)") { PiliLiveAreaRoomsView(api: api, title: group.name, parentID: group.id, areaID: 0) } }
                    ForEach(group.children.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { area in
                        NavigationLink(area.name) { PiliLiveAreaRoomsView(api: api, title: area.name, parentID: group.id, areaID: area.id) }
                    }
                }
            }
        }.navigationTitle("直播分区").searchable(text: $query, prompt: "搜索分区")
            .task { if areas.isEmpty { await load() } }
    }
    private func load() async {
        guard !loading else { return }; loading = true; error = nil
        defer { loading = false }
        do { areas = try await api.fetchLiveAreas() } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

private struct PiliLiveAreaRoomsView: View {
    let api: BiliAPIClient
    let title: String
    let parentID: Int?
    let areaID: Int
    @State private var rooms: [LiveRoom] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var busy = false
    @State private var error: String?
    @State private var identity: PiliAccountIdentity?
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(rooms) { room in NavigationLink(value: room) { LiveRoomCard(room: room) }.buttonStyle(.plain) }
                if let error { Text(error); Button("重试") { Task { await load() } } }
                if busy { ProgressView() }
                else if hasMore { Button("加载更多") { Task { await load() } } }
                else if rooms.isEmpty { ContentUnavailableView("暂无直播", systemImage: "dot.radiowaves.left.and.right") }
            }.padding()
        }.navigationTitle(title).task { if identity == nil { identity = .init(api.requestSnapshot()); await load() } }
    }
    private func load() async {
        guard !busy, hasMore, let identity else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            var incoming: [LiveRoom] = [], more = true
            var cursor = page
            if let parentID { incoming = try await api.fetchLiveRooms(parentAreaID: parentID, areaID: areaID, page: page); more = incoming.count >= 20 }
            else {
                // Followed rooms can have an empty page after filtering offline hosts.
                for index in 0..<5 {
                    let result = try await api.piliFollowedLiveRooms(page: cursor, identity: identity)
                    incoming.append(contentsOf: result.rooms); more = result.more
                    if !incoming.isEmpty || !more { break }; if index < 4 { cursor += 1 }
                }
            }
            guard !Task.isCancelled, identity.matches(api.requestSnapshot()) else { throw CancellationError() }
            var seen = Set(rooms.map(\.roomID)); let next = incoming.filter { seen.insert($0.roomID).inserted }
            rooms.append(contentsOf: next); hasMore = more && (parentID == nil || !next.isEmpty); page = cursor + 1
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct PiliMedalWallView: View {
    let mid: Int
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var medals: [DynamicJSONValue] = []
    @State private var loaded = false
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error); Button("重试") { Task { await load() } } }
            if !loaded && error == nil { ProgressView() }
            if loaded && medals.isEmpty { Text("暂无公开的粉丝勋章") }
            ForEach(medals, id: \.self) { medal in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(medal["uinfo_medal"]["name"].piliString) · Lv\(medal["uinfo_medal"]["level"].piliInt)").font(.headline)
                    Text(medal["target_name"].piliString).foregroundStyle(.secondary)
                    if medal["medal_info"]["wearing_status"].piliInt == 1 { Text("正在佩戴").font(.caption) }
                    if let url = URL(string: medal["link"].piliString), ["https", "http", "bilibili"].contains(url.scheme ?? "") {
                        AppLinkButton(url: url) { Label("进入直播间", systemImage: "dot.radiowaves.left.and.right") }
                    }
                }
            }
        }.navigationTitle("粉丝勋章").task { if !loaded { await load() } }
    }
    private func load() async {
        error = nil
        do {
            let data = try await dependencies.api.piliContentRead("/xlive/web-ucenter/user/MedalWall", query: ["target_id": String(mid)], base: BiliAPIClient.piliLiveBase)
            guard !Task.isCancelled else { return }
            var seen = Set<DynamicJSONValue>(); medals = data["list"].piliArray.filter { seen.insert($0).inserted }; loaded = true
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
