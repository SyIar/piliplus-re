import SwiftUI
import ChunUI

struct PiliPGCCatalogueView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var type = 1
    @State private var conditions: PiliPGCConditions?
    @State private var filters: [String: String] = [:]
    @State private var draft: [String: String] = [:]
    @State private var items: [SearchMediaItem] = []
    @State private var page = 1
    @State private var more = true
    @State private var loading = false
    @State private var generation = UUID()
    @State private var error: String?
    @State private var showsFilters = false
    private let types = [(1, "番剧"), (4, "国创"), (2, "电影"), (3, "纪录片"), (5, "电视剧"), (7, "综艺")]
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack {
                    Picker("内容类型", selection: $type) { ForEach(types, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.menu)
                    Spacer()
                    PiliIconButton("筛选", systemImage: "line.3.horizontal.decrease") { draft = filters; showsFilters = true }.disabled(conditions == nil)
                }
                NavigationLink { PiliPGCTimelineView(api: dependencies.api, type: type) } label: { PiliLabel("更新日历", systemImage: "calendar") }
                ForEach(items) { media in SearchResultRouteRow(result: type == 1 || type == 4 ? .bangumi(media) : .movie(media)) }
                if let error { Text(error).piliFont(.sm); Button("重试") { Task { if conditions == nil { await reload() } else { await loadPage() } } } }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                else if more { Button("加载更多") { Task { await loadPage() } }.frame(maxWidth: .infinity) }
                else if items.isEmpty { PiliUnavailableView("暂无符合条件的内容", systemImage: "film") }
            }.padding()
        }.navigationTitle("番剧与影视").navigationBarTitleDisplayMode(.inline)
            .task(id: type) { await reload() }
            .refreshable { await reload() }
            .piliSheet(isPresented: $showsFilters) { filterSheet }
    }
    private var filterSheet: some View {
        NavigationStack {
            PiliForm {
                if let conditions {
                    if !conditions.order.isEmpty {
                        Picker("排序", selection: value("order")) { ForEach(conditions.order) { Text($0.title).tag($0.id) } }
                        Picker("顺序", selection: value("sort")) { Text("降序").tag("0"); Text("升序").tag("1") }
                    }
                    ForEach(conditions.filters) { filter in
                        Picker(filter.title, selection: value(filter.id)) { ForEach(filter.values) { Text($0.title).tag($0.id) } }
                    }
                    Button("重置筛选") { draft = conditions.defaults }
                }
            }.navigationTitle("筛选")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showsFilters = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("应用") {
                        filters = draft; showsFilters = false
                        generation = UUID(); loading = false; items = []; page = 1; more = true
                        Task { await loadPage() }
                    } }
                }
        }
    }
    private func value(_ field: String) -> Binding<String> { Binding(get: { draft[field] ?? "" }, set: { draft[field] = $0 }) }
    private func reload() async {
        let ticket = UUID(); generation = ticket; loading = true; error = nil; items = []; page = 1; more = true; conditions = nil
        do {
            let value = try await dependencies.api.piliPGCConditions(type: type)
            guard !Task.isCancelled, generation == ticket else { return }
            conditions = value; filters = value.defaults; loading = false
            await loadPage()
        } catch {
            guard !Task.isCancelled, generation == ticket else { return }
            loading = false; self.error = error.localizedDescription
        }
    }
    private func loadPage() async {
        guard !loading, more else { return }
        let ticket = generation; loading = true; error = nil
        defer { if generation == ticket { loading = false } }
        do {
            let result = try await dependencies.api.piliPGCCatalogue(type: type, page: page, filters: filters)
            guard !Task.isCancelled, generation == ticket else { return }
            var seen = Set(items.map(\.id)); let incoming = result.items.filter { seen.insert($0.id).inserted }
            items.append(contentsOf: incoming); page += 1; more = result.more && !incoming.isEmpty
        } catch { if !Task.isCancelled, generation == ticket { self.error = error.localizedDescription } }
    }
}

private struct PiliPGCTimelineView: View {
    let api: BiliAPIClient
    let type: Int
    @State private var days: [PiliPGCTimelineDay] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        PiliList {
            if loading { ProgressView() }
            if let error { Text(error); Button("重试") { Task { await load() } } }
            ForEach(days) { day in
                Section(day.title) {
                    if day.episodes.isEmpty { Text("暂无更新").foregroundStyle(.secondary) }
                    ForEach(day.episodes) { episode in
                        if let url = URL(string: "https://www.bilibili.com/bangumi/play/ep\(episode.id)") {
                            AppLinkButton(url: url) {
                                HStack {
                                    SearchPosterCover(sourceURLString: episode.cover, thumbnailWidth: 144, thumbnailHeight: 192,
                                                      targetPixelSize: 192, size: CGSize(width: 48, height: 64), placeholderSystemImage: "film")
                                    VStack(alignment: .leading) { Text(episode.title).lineLimit(2); Text(episode.detail).piliFont(.sm).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
            }
        }.navigationTitle("更新日历").task { await load() }.refreshable { await load() }
    }
    private func load() async {
        guard !loading else { return }; loading = true; error = nil
        defer { loading = false }
        do { let value = try await api.piliPGCTimeline(type: type); if !Task.isCancelled { days = value } }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
