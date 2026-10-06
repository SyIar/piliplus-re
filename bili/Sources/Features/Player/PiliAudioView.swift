import Combine
import SwiftUI
import PiliPlaybackCore

@MainActor
final class PiliAudioModel: ObservableObject {
    @Published var tracks: [PiliAudioTrack] = []
    @Published var selected: PiliAudioTrack?
    @Published var sources: [PiliAudioSource] = []
    @Published var sourceID = 0
    @Published var player: PlayerStateViewModel?
    @Published var next: String?
    @Published var busy = false
    @Published var error: String?
    @Published var liked = false
    @Published var order: VideoListenPlaylistSortOrder = .normal
    let api: BiliAPIClient
    let anchor: Int
    private var generation = UUID()
    private var returnPosition = 0.0
    init(api: BiliAPIClient, id: Int) { self.api = api; anchor = id }

    func load(reset: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let ticket = generation
        do {
            let page = try await api.piliAudioPlaylist(id: anchor, cursor: reset ? nil : next, order: order)
            guard generation == ticket, !Task.isCancelled else { return }
            if reset { tracks = [] }
            var seen = Set(tracks.map(\.id)); tracks.append(contentsOf: page.items.filter { seen.insert($0.id).inserted })
            next = page.next; error = nil
            if selected == nil, let track = tracks.first(where: { $0.id == anchor }) ?? tracks.first { await select(track) }
            if tracks.isEmpty { error = "此音频已失效或当前账号无法查看" }
        } catch { if !Task.isCancelled, generation == ticket { self.error = error.localizedDescription } }
    }
    func select(_ track: PiliAudioTrack, resume: Bool = false) async {
        if !resume { returnPosition = 0 }
        generation = UUID(); let ticket = generation; player?.stop(); player = nil; sources = []; selected = track; liked = track.liked; error = nil
        do {
            let sources = try await api.piliAudioSources(track.item)
            guard generation == ticket, !Task.isCancelled else { return }
            self.sources = sources
            if let source = sources.first { install(source) }
        } catch { if generation == ticket, !Task.isCancelled { self.error = error.localizedDescription } }
    }
    func install(_ source: PiliAudioSource) {
        guard let track = selected else { return }
        let position = player?.currentTime ?? returnPosition; returnPosition = 0; player?.stop(); sourceID = source.id
        let current = PlayerStateViewModel(videoURL: nil, audioURL: source.url, title: track.title, authorName: track.owner.name,
            referer: "https://www.bilibili.com/audio/au\(track.id)", durationHint: source.duration > 0 ? source.duration : Double(track.duration),
            resumeTime: position, startupResumePolicy: .immediate, artworkURL: URL(string: track.cover.normalizedBiliURL()), playbackContentMode: .audioOnly)
        player = current
        current.setTrackNavigationAvailability(hasPrevious: tracks.first?.id != track.id, hasNext: tracks.last?.id != track.id || next != nil)
        current.onNextTrackRequested = { [weak self] in Task { await self?.navigate(1) } }
        current.onPreviousTrackRequested = { [weak self] in Task { await self?.navigate(-1) } }
        current.onPlaybackEnded = { [weak self, weak current] in
            guard let self, let current else { return }
            Task { await self.finishPlayback(current) }
        }
        current.play()
    }
    func navigate(_ offset: Int, manual: Bool = true) async {
        guard let id = selected?.id, let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        if manual { PiliSleepTimer.shared.resumeManually() }
        if index + offset >= tracks.count, next != nil { await load() }
        guard tracks.indices.contains(index + offset) else { return }
        await select(tracks[index + offset])
    }
    private func finishPlayback(_ current: PlayerStateViewModel) async {
        guard player === current, let track = selected else { return }
        if PiliSleepTimer.shared.shouldStopAtPlaybackEnd() { current.pause(); return }
        let order = PiliPlaybackPreferences.shared.order
        if order != .stop, order != .repeatOne, tracks.last?.id == track.id, next != nil { await load() }
        guard player === current else { return }
        let action = PlaybackEndPolicy.resolve(order: order, currentIndex: tracks.firstIndex { $0.id == track.id }, count: tracks.count,
            sleepTimerStops: PiliSleepTimer.shared.shouldStopAtPlaybackEnd())
        switch action {
        case .stop: current.pause()
        case .replay: current.seek(to: 0); current.play()
        case let .advance(index): await select(tracks[index])
        case .loadRelated: await navigate(1, manual: false)
        }
    }
    func leave() { generation = UUID(); returnPosition = player?.currentTime ?? 0; player?.stop(); player = nil }
}

struct PiliAudioView: View {
    @StateObject private var model: PiliAudioModel
    @State private var comments: DynamicFeedItem?
    @State private var actionBusy = false
    @State private var confirmCoin = false
    @State private var confirmTriple = false
    @State private var favorites = false
    init(api: BiliAPIClient, id: Int) { _model = .init(wrappedValue: PiliAudioModel(api: api, id: id)) }
    var body: some View {
        List {
            if let track = model.selected {
                if let player = model.player { PiliOfflineAudioControls(player: player, title: track.title, author: track.owner.name).listRowBackground(Color.clear) }
                else if model.error == nil { ProgressView("正在获取音轨") }
                VideoOwnerRouteLink(owner: track.owner) { Label(track.owner.name, systemImage: "person.crop.circle") }
                if !track.description.isEmpty { Text(track.description).font(.subheadline).textSelection(.enabled) }
                HStack {
                    Button("赞", systemImage: model.liked ? "hand.thumbsup.fill" : "hand.thumbsup") { action("ThumbUp") }
                        .contextMenu { Button("三连") { confirmTriple = true } }
                    Button("投币", systemImage: "c.circle") { confirmCoin = true }
                    Button("收藏", systemImage: "star") { favorites = true }
                    Button("评论", systemImage: "bubble") { comments = try? piliCommentTarget(oid: String(track.id), type: 14, author: track.owner) }
                }.buttonStyle(.borderless).disabled(actionBusy)
                if model.sources.count > 1 {
                    Picker("音质", selection: Binding(get: { model.sourceID }, set: { id in if let source = model.sources.first(where: { $0.id == id }) { model.install(source) } })) {
                        ForEach(model.sources) { Text($0.title).tag($0.id) }
                    }
                }
                if let player = model.player {
                    Picker("播放速度", selection: Binding(get: { player.playbackRate }, set: { player.setPlaybackRate($0) })) {
                        ForEach(BiliPlaybackRate.allCases, id: \.self) { Text("\($0.rawValue, specifier: "%.2g")×").tag($0) }
                    }
                }
                ShareLink(item: URL(string: "https://www.bilibili.com/audio/au\(track.id)")!)
            }
            if let error = model.error { Text(error).foregroundStyle(.red); Button("重试") { Task { if let track = model.selected { await model.select(track) } else { await model.load(reset: true) } } } }
            Section("播放列表") {
                Picker("排序", selection: $model.order) { ForEach(VideoListenPlaylistSortOrder.allCases) { Text($0.title).tag($0) } }.disabled(model.busy)
                ForEach(model.tracks) { track in
                    Button { Task { await model.select(track) } } label: {
                        Label(track.title, systemImage: track.id == model.selected?.id ? "speaker.wave.2.fill" : "music.note")
                    }.disabled(model.busy)
                }
                if model.busy { ProgressView() }
                else if model.next != nil { Button("加载更多") { Task { await model.load() } } }
            }
        }.navigationTitle("音频").task { if model.tracks.isEmpty { await model.load(reset: true) } else if model.player == nil, let track = model.selected { await model.select(track, resume: true) } }
            .onChange(of: model.order) { Task { await model.load(reset: true) } }
            .onDisappear { model.leave() }
            .sheet(item: $comments) { DynamicCommentsSheet(item: $0, api: model.api) }
            .sheet(isPresented: $favorites) { if let track = model.selected { NavigationStack { PiliAudioFavoritesView(api: model.api, id: track.id) } } }
            .confirmationDialog("选择投币数量", isPresented: $confirmCoin, titleVisibility: .visible) { Button("投 1 枚硬币") { action("CoinAdd", coins: 1) }; Button("投 2 枚硬币") { action("CoinAdd", coins: 2) } }
            .confirmationDialog("点赞、投币并收藏？", isPresented: $confirmTriple, titleVisibility: .visible) { Button("三连") { action("TripleLike") } }
            .toolbar { Button("播放方式", systemImage: "timer") { PiliPlaybackToolsView.present() } }
    }
    private func action(_ method: String, coins: Int = 1) {
        guard !actionBusy, let track = model.selected else { return }; actionBusy = true
        Task {
            defer { actionBusy = false }
            do {
                let identity = PiliAccountIdentity(await model.api.requestSnapshot(purpose: .interaction))
                let response = try await model.api.piliAudioAction(method, item: track.item, liked: model.liked, coins: coins, identity: identity)
                if model.selected?.id == track.id {
                    if method == "ThumbUp" { model.liked.toggle() }
                    if method == "TripleLike" { if response.integer(2) != 0 { model.liked = true }; model.error = response.string(1).isEmpty ? "已提交三连，请以服务端状态为准" : response.string(1) }
                }
            } catch { model.error = error.localizedDescription }
        }
    }
}

private struct PiliAudioFavoritesView: View {
    let api: BiliAPIClient
    let id: Int
    @Environment(\.dismiss) private var dismiss
    @State private var folders: [DynamicJSONValue] = []
    @State private var initial = Set<Int>()
    @State private var selection = Set<Int>()
    @State private var identity: PiliAccountIdentity?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        List {
            ForEach(folders, id: \.self) { folder in
                Toggle(folder["title"].piliString, isOn: Binding(get: { selection.contains(folder["id"].piliInt) }, set: { on in
                    if on { selection.insert(folder["id"].piliInt) } else { selection.remove(folder["id"].piliInt) }
                }))
            }
            if let error { Text(error).foregroundStyle(.red) }
            if busy { ProgressView() }
            Button("保存") { Task { await save() } }.disabled(busy || identity == nil || initial == selection)
        }.navigationTitle("收藏音频").task {
            busy = true; defer { busy = false }
            do {
                let identity = PiliAccountIdentity(await api.requestSnapshot(purpose: .interaction)); self.identity = identity
                let data = try await api.piliContentRead("/x/v3/fav/folder/created/list-all", query: ["up_mid": String(identity.mid), "type": "12", "rid": String(id)], purpose: .interaction, identity: identity)
                folders = data["list"].piliArray; initial = Set(folders.filter { $0["fav_state"].piliInt == 1 }.map { $0["id"].piliInt }); selection = initial
            } catch { self.error = error.localizedDescription }
        }.toolbar { Button("关闭") { dismiss() } }
    }
    private func save() async {
        guard !busy, let identity else { return }; busy = true; defer { busy = false }
        do {
            try await api.piliContentWrite("/x/v3/fav/resource/deal", fields: ["rid": String(id), "type": "12", "add_media_ids": selection.subtracting(initial).sorted().map(String.init).joined(separator: ","), "del_media_ids": initial.subtracting(selection).sorted().map(String.init).joined(separator: ",")], identity: identity, purpose: .interaction)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
