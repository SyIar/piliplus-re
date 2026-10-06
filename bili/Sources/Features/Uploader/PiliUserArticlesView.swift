import SwiftUI
import ChunUI

struct PiliUserArticlesView: View {
    let api: BiliAPIClient
    let mid: Int
    @State private var items: [DynamicJSONValue] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        PiliList {
            ForEach(items, id: \.self) { item in
                if let url = URL(string: item["uri"].piliString), let route = PiliArticleRoute(url: url) {
                    NavigationLink { PiliArticleView(api: api, route: route) } label: { row(item) }
                } else if let url = URL(string: item["uri"].piliString) { Link(destination: url) { row(item) } }
                else { row(item) }
            }
            if let error { Text(error).foregroundStyle(Color.cc.destructive); Button("重试") { Task { await load() } } }
            else if busy { ProgressView() }
            else if hasMore { Button("加载更多") { Task { await load() } } }
            else if items.isEmpty { Text("暂无图文") }
        }.navigationTitle("用户图文").task { if items.isEmpty { await load() } }
    }
    private func row(_ item: DynamicJSONValue) -> some View {
        HStack {
            if let raw = item["origin_image_urls"].piliArray.first?.piliString {
                CachedRemoteImage(url: URL(string: raw.normalizedBiliURL()), targetPixelSize: 240) { $0.resizable().scaledToFill() } placeholder: { Color.clear }.frame(width: 80, height: 60).clipped()
            }
            VStack(alignment: .leading, spacing: 5) { Text(item["title"].piliString); Text(item["publish_time_text"].piliString).piliFont(.sm).foregroundStyle(.secondary) }
        }
    }
    private func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let data = try await api.piliUserArticles(mid: mid, page: page), list = data["item"].piliArray
            var seen = Set(items.map { $0["uri"].piliString }); items.append(contentsOf: list.filter { seen.insert($0["uri"].piliString).inserted })
            hasMore = list.count >= 10 && items.count < data["count"].piliInt; page += 1; error = nil
        } catch { self.error = error.localizedDescription }
    }
}
