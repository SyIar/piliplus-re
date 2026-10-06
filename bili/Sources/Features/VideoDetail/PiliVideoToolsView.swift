import SwiftUI

extension EnvironmentValues {
    @Entry var piliVideoTools: PiliVideoToolsController? = nil
}

struct PiliVideoToolsOverlay: View {
    let model: VideoDetailViewModel
    @ObservedObject var store: PiliVideoToolsController
    @ObservedObject var clock: PlayerPlaybackClock
    var body: some View {
        VStack {
            Spacer()
            if let clip = store.currentClip {
                HStack {
                    Spacer()
                    Button("跳过\(clip.title)", systemImage: "forward.end") { store.skip(clip, model: model) }
                        .buttonStyle(.glass).padding(.trailing, 18).padding(.bottom, 105)
                }
            }
        }
        .task(id: "\(model.detail.bvid)|\(model.selectedCID ?? 0)|\(model.api.requestSnapshot(purpose: .playback).playbackCredentialVersion)") {
            do {
                while model.stablePlayerViewModel?.hasPresentedPlayback != true {
                    guard !model.isPlaybackInvalidatedForNavigation else { return }
                    try await Task.sleep(for: .milliseconds(150))
                }
                await store.load(model)
            } catch {}
        }
        .onReceive(clock.$currentTime) { store.tick($0, model: model) }
    }
}

struct PiliEnergyStrip: View {
    @ObservedObject var store: PiliVideoToolsController
    @AppStorage("piliplus.player.energy") private var enabled = true
    var body: some View {
        if enabled, let energy = store.energy {
            PiliEnergyGraph(values: energy.values).equatable().accessibilityLabel("高能进度条")
        }
    }
}
private struct PiliEnergyGraph: View, Equatable {
    let values: [Double]
    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            guard values.count > 1 else { return }
            var path = Path(); path.move(to: CGPoint(x: 0, y: size.height))
            for (index, value) in values.enumerated() {
                path.addLine(to: CGPoint(x: Double(index) / Double(values.count - 1) * size.width, y: (1 - value) * size.height))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height)); path.closeSubpath()
            context.fill(path, with: .linearGradient(Gradient(colors: [.blue.opacity(0.7), .blue.opacity(0.1)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        }.allowsHitTesting(false)
    }
}

struct PiliVideoToolsView: View {
    let model: VideoDetailViewModel
    @ObservedObject var store: PiliVideoToolsController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("画面") { PiliVideoAspectPicker() }
                if store.loading { ProgressView("加载视频信息") }
                if let error = store.error { Text(error); Button("重试") { Task { await store.retry(model) } } }
                if store.energy != nil {
                    Section("高能进度") { PiliEnergyStrip(store: store).frame(height: 54); Text("由弹幕密度生成，曲线与当前分 P 对应。").font(.caption) }
                }
                Section("视频章节") {
                    if store.chapters.isEmpty { Text("此视频未提供章节") }
                    ForEach(store.chapters) { chapter in
                        Button {
                            model.stablePlayerViewModel?.seek(to: chapter.start); dismiss()
                        } label: {
                            HStack {
                                if !chapter.image.isEmpty {
                                    CachedRemoteImage(url: URL(string: chapter.image), targetPixelSize: 240) { $0.resizable().scaledToFill() }
                                        placeholder: { Color.gray.opacity(0.1) }.frame(width: 80, height: 45).clipped()
                                }
                                VStack(alignment: .leading) { Text(chapter.title); Text(BiliFormatters.duration(Int(chapter.start))).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                if !store.staff.isEmpty {
                    Section("联合创作") {
                        ForEach(store.staff) { person in
                            NavigationLink { UploaderView(owner: person.owner) } label: {
                                HStack { Text(person.owner.name); Spacer(); Text(person.role).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                if !store.tags.isEmpty {
                    Section("标签") {
                        ForEach(store.tags) { tag in
                            NavigationLink { PiliKeywordSearchView(api: model.api, keyword: tag.title) } label: { Label(tag.title, systemImage: "number") }
                        }
                    }
                }
            }.navigationTitle("章节与视频信息").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .task { await store.load(model) }
        }
    }
}

struct PiliKeywordSearchView: View {
    @StateObject private var model: SearchViewModel
    @StateObject private var accessory = SearchBottomAccessoryStore()
    let keyword: String
    private let api: BiliAPIClient
    init(api: BiliAPIClient, keyword: String) {
        self.keyword = keyword; self.api = api; _model = StateObject(wrappedValue: SearchViewModel(api: api))
    }
    var body: some View {
        SearchContentView(viewModel: model, showsHotSearches: true, accessoryStore: accessory)
            .videoDestinations()
            .navigationDestination(for: PiliArticleRoute.self) { PiliArticleView(api: api, route: $0) }
            .navigationDestination(for: PiliCourseRoute.self) { PiliCoursePlaybackView(api: api, route: $0) }
            .navigationTitle(keyword).searchable(text: $model.query, prompt: model.searchPrompt)
            .onSubmit(of: .search) { Task { await model.search() } }
            .task { if model.results.isEmpty { await model.search(keyword) } }
    }
}
