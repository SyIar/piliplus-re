import SwiftUI

struct PiliDiscoveryView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var mode = 0
    @State private var issues: [PiliWeeklyIssue] = []
    @State private var issue = 0
    @State private var rank = PiliRankCategory.all[0]
    @State private var videos: [VideoItem] = []
    @State private var media: [SearchMediaItem] = []
    @State private var page = 1
    @State private var more = false
    @State private var loading = false
    @State private var generation = UUID()
    @State private var error: String?
    private var queryID: String { "\(mode)-\(issue)-\(rank.id)" }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Picker("发现", selection: $mode) { Text("每周必看").tag(0); Text("入站必刷").tag(1); Text("排行榜").tag(2) }.pickerStyle(.segmented)
                if mode == 0, !issues.isEmpty { Picker("期数", selection: $issue) { ForEach(issues) { Text($0.title).tag($0.id) } } }
                if mode == 2 { Picker("分区", selection: $rank) { ForEach(PiliRankCategory.all) { Text($0.title).tag($0) } } }
                ForEach(videos) { video in VideoRouteLink(video) { SearchVideoResultRow(video: video) } }
                ForEach(media) { SearchResultRouteRow(result: .bangumi($0)) }
                if let error { Text(error); Button("重试") { Task { await reload() } } }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                else if more { Button("加载更多") { Task { await loadPage() } }.frame(maxWidth: .infinity) }
                else if error == nil, videos.isEmpty, media.isEmpty { ContentUnavailableView("暂无内容", systemImage: "play.rectangle") }
            }.padding()
        }.navigationTitle("发现好视频").navigationBarTitleDisplayMode(.inline)
            .task(id: queryID) { await reload() }.refreshable { await reload() }
    }
    private func reload() async {
        generation = UUID(); let ticket = generation
        loading = true; error = nil; videos = []; media = []; page = 1; more = true
        if mode == 0, issues.isEmpty {
            do {
                let values = try await dependencies.api.piliWeeklyIssues()
                guard !Task.isCancelled, generation == ticket else { return }
                issues = values
                if let first = values.first, issue != first.id { issue = first.id; loading = false; return }
            } catch {
                if !Task.isCancelled, generation == ticket { self.error = error.localizedDescription; loading = false }
                return
            }
        }
        guard !Task.isCancelled, generation == ticket else { return }
        loading = false
        if mode == 0, issue == 0 { more = false; return }
        await loadPage()
    }
    private func loadPage() async {
        guard !loading, more else { return }; loading = true; error = nil
        let ticket = generation
        defer { if generation == ticket { loading = false } }
        do {
            let result = try await dependencies.api.piliDiscoveryVideos(weekly: mode == 0 ? issue : nil, preciousPage: mode == 1 ? page : nil, rank: mode == 2 ? rank : nil)
            guard !Task.isCancelled, generation == ticket else { return }
            var seen = Set(videos.map(\.id))
            let incoming = result.videos.filter { seen.insert($0.id).inserted }
            videos.append(contentsOf: VideoRecommendationFilter.filtered(incoming, configuration: libraryStore.videoRecommendationFilterConfiguration, context: .feed))
            var seasons = Set(media.map(\.id)); media.append(contentsOf: result.media.filter { seasons.insert($0.id).inserted })
            more = result.more && !incoming.isEmpty; page += 1
        } catch { if !Task.isCancelled, generation == ticket { self.error = error.localizedDescription } }
    }
}
