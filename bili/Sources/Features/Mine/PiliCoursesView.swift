import SwiftUI
import ChunUI

struct PiliCoursesView: View {
    let api: BiliAPIClient
    var ownerMID: Int?
    @State private var items: [DynamicJSONValue] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        PiliList {
            ForEach(items, id: \.self) { item in
                NavigationLink {
                    PiliCoursePlaybackView(api: api, route: .init(seasonID: item["season_id"].piliInt))
                } label: {
                    HStack {
                        CachedRemoteImage(url: URL(string: item["cover"].piliString.normalizedBiliURL()), targetPixelSize: 260) { $0.resizable().scaledToFill() } placeholder: { Color.clear }.frame(width: 90, height: 60).clipped()
                        VStack(alignment: .leading, spacing: 5) { Text(item["title"].piliString); Text(item["status"].piliString).piliFont(.sm).foregroundStyle(.secondary) }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(Color.cc.destructive); Button("重试") { Task { await load() } } }
            else if busy { ProgressView() }
            else if hasMore { Button("加载更多") { Task { await load() } } }
            else if items.isEmpty { Text("暂无课程") }
        }.navigationTitle(ownerMID == nil ? "收藏的课程" : "用户课程").task { if items.isEmpty { await load() } }
    }
    private func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let identity = PiliAccountIdentity(api.requestSnapshot(purpose: .main))
        guard let mid = ownerMID ?? (identity.mid > 0 ? identity.mid : nil) else { error = "请先登录"; return }
        do {
            let response = try await api.piliCourseList(mid: mid, page: page, favorites: ownerMID == nil)
            if ownerMID == nil && !identity.matches(api.requestSnapshot(purpose: .main)) { throw PiliOfflineError.message("账号已切换") }
            let list = response["items"].piliArray
            var seen = Set(items.map { $0["season_id"].piliInt }); items.append(contentsOf: list.filter { seen.insert($0["season_id"].piliInt).inserted })
            let total = response["page"]["total"].piliInt
            hasMore = list.count >= 20 && (total == 0 || items.count < total); page += 1; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct PiliCoursePlaybackView: View {
    let api: BiliAPIClient
    let route: PiliCourseRoute
    @State private var video: VideoItem?
    @State private var error: String?
    var body: some View {
        Group {
            if let video { VideoDetailView(seedVideo: video) }
            else if let error { ContentUnavailableView { PiliLabel("课程加载失败", systemImage: "exclamationmark.triangle") } description: { Text(error) } actions: { Button("重试") { Task { await load() } } } }
            else { ProgressView("加载课程") }
        }.task(id: route) { await load() }
    }
    private func load() async {
        do {
            let season = try await api.piliCourseSeason(seasonID: route.seasonID, episodeID: route.episodeID)
            let episode = route.episodeID.flatMap { id in season.allPlayableEpisodes.first { $0.id == id } } ?? season.preferredPlaybackEpisode
            guard let video = episode?.videoItem(in: season) else { throw PiliOfflineError.message("课程暂无可播放分集") }
            self.video = video; error = nil
        } catch { self.error = error.localizedDescription }
    }
}
