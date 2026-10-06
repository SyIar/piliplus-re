import SwiftUI

struct PiliPublicFavoriteView: View {
    let api: BiliAPIClient
    let folder: FavoriteFolder
    var seasonID: Int? = nil
    @State private var items: [DynamicJSONValue] = []
    @State private var keyword = ""
    @State private var order = PiliFavoriteOrder.favoriteTime
    @State private var page = 1
    @State private var more = true
    @State private var busy = false
    @State private var favorited = false
    @State private var loadedInfo = false
    @State private var ownsFolder = false
    @State private var identity: PiliAccountIdentity?
    @State private var error: String?
    @State private var generation = UUID()
    var body: some View {
        List {
            if seasonID == nil { Picker("排序", selection: $order) { ForEach(PiliFavoriteOrder.allCases) { Text($0.title).tag($0) } }.disabled(busy) }
            if loadedInfo && !ownsFolder { Button(favorited ? "取消订阅收藏夹" : "订阅收藏夹", systemImage: favorited ? "star.fill" : "star") { subscribe() }.disabled(busy) }
            ForEach(items, id: \.self) { item in
                if let url = resourceURL(item) {
                    AppLinkButton(url: url) {
                        HStack {
                            CachedRemoteImage(url: URL(string: item["cover"].piliString.normalizedBiliURL()), targetPixelSize: 240) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.1) }.frame(width: 80, height: 50).clipped()
                            Text(item["title"].piliString).lineLimit(3)
                        }
                    }
                } else { Text(item["title"].piliString).foregroundStyle(.secondary) }
            }
            if busy { ProgressView() }
            else if let error { Text(error).foregroundStyle(.red); Button("重试") { Task { await load() } } }
            else if more { Button("加载更多") { Task { await load() } } }
            else if items.isEmpty { Text("没有匹配的内容") }
        }.navigationTitle(folder.displayTitle).searchable(text: $keyword, prompt: "搜索收藏夹")
            .task { identity = PiliAccountIdentity(api.requestSnapshot()); await load(reset: true) }
            .onSubmit(of: .search) { Task { await load(reset: true) } }.onChange(of: order) { Task { await load(reset: true) } }
            .refreshable { await load(reset: true) }
    }
    private func resourceURL(_ item: DynamicJSONValue) -> URL? {
        if item["type"].piliInt == 12 { return URL(string: "https://www.bilibili.com/audio/au\(item["id"].piliInt)") }
        if !item["bvid"].piliString.isEmpty { return URL(string: "https://www.bilibili.com/video/\(item["bvid"].piliString)") }
        if item["type"].piliInt == 2, item["id"].piliInt > 0 { return URL(string: "https://www.bilibili.com/video/av\(item["id"].piliInt)") }
        return nil
    }
    private func load(reset: Bool = false) async {
        if reset { generation = UUID(); page = 1; items = []; more = true }
        else if busy || !more { return }
        let ticket = generation; busy = true; error = nil; defer { if ticket == generation { busy = false } }
        do {
            let data = try await api.piliContentRead(seasonID == nil ? "/x/v3/fav/resource/list" : "/x/space/fav/season/list", query: [seasonID == nil ? "media_id" : "season_id": String(folder.id), "pn": String(page), "ps": "20", "keyword": keyword, "order": order.rawValue, "type": "0", "tid": "0", "platform": "web"])
            guard generation == ticket, !Task.isCancelled else { return }
            favorited = data["info"]["fav_state"].piliInt == 1; loadedInfo = true
            ownsFolder = max(data["info"]["mid"].piliInt, data["info"]["upper"]["mid"].piliInt) == identity?.mid
            var seen = Set(items); let fresh = data["medias"].piliArray.filter { seen.insert($0).inserted }
            items.append(contentsOf: fresh); page += 1; more = (seasonID == nil ? data["has_more"].piliInt != 0 : items.count < data["info"]["media_count"].piliInt) && !fresh.isEmpty
        } catch { if generation == ticket, !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func subscribe() {
        guard let identity, !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do { try await api.piliContentWrite((seasonID == nil ? "/x/v3/fav/folder/" : "/x/v3/fav/season/") + (favorited ? "unfav" : "fav"), fields: [seasonID == nil ? "media_id" : "season_id": String(folder.id), "platform": "web"], identity: identity); favorited.toggle() }
            catch { self.error = error.localizedDescription }
        }
    }
}
