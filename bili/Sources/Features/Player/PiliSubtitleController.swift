import Combine
import Foundation
import PiliPlaybackCore

@MainActor
final class PiliSubtitleController: ObservableObject {
    @Published private(set) var tracks: [PiliSubtitleTrack] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var timeline = SubtitleTimeline([])
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var cache: [String: [SubtitleCue]] = [:]
    private var selectionGeneration = UUID()
    private var selectionTask: Task<Void, Never>?
    private var contextID: String?
    private var generation = UUID()
    private var api: BiliAPIClient?

    func load(video: VideoItem, cid: Int, api: BiliAPIClient) async {
        let context = "\(video.bvid)|\(cid)|\(api.requestSnapshot(purpose: .playback).playbackCredentialVersion)"
        guard contextID != context else { return }
        reset()
        contextID = context; self.api = api
        let token = generation
        isLoading = true
        defer {
            if generation == token {
                if Task.isCancelled { contextID = nil }
                if selectionTask == nil { isLoading = false }
            }
        }
        do {
            let metadata = try await api.fetchPiliPlayerMetadata(bvid: video.bvid, cid: cid,
                                                                seasonID: video.pgcSeasonID, episodeID: video.pgcEpisodeID)
            guard !Task.isCancelled, generation == token else { return }
            tracks = (metadata.subtitle?.subtitles ?? []).sorted {
                if $0.lan.contains("zh") != $1.lan.contains("zh") { return $0.lan.contains("zh") }
                return !$0.isAI && $1.isAI
            }
            selectPreferred()
        } catch {
            guard !Task.isCancelled, generation == token else { return }
            errorMessage = "字幕加载失败：\(error.localizedDescription)"
            contextID = nil
        }
    }
    func loadOffline(_ values: [PiliCachedSubtitle]) {
        reset()
        tracks = values.map(\.track)
        cache = Dictionary(values.map { ($0.track.id, $0.cues) }, uniquingKeysWith: { first, _ in first })
        selectPreferred()
    }
    func select(_ id: String?, remember: Bool = true) {
        selectionTask?.cancel(); selectionTask = nil
        selectionGeneration = UUID()
        let selectionToken = selectionGeneration
        selectedID = id; timeline = SubtitleTimeline([]); errorMessage = nil
        if remember {
            UserDefaults.standard.set(id == nil ? "off" : "on", forKey: "piliplus.subtitle.mode")
            if let track = tracks.first(where: { $0.id == id }) { UserDefaults.standard.set(track.lan, forKey: "piliplus.subtitle.language") }
        }
        guard let id else { isLoading = false; return }
        if let values = cache[id] { timeline = SubtitleTimeline(values); isLoading = false; return }
        guard let api, let track = tracks.first(where: { $0.id == id }) else { return }
        let token = generation
        isLoading = true
        selectionTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token && self.selectionGeneration == selectionToken { self.isLoading = false; self.selectionTask = nil } }
            do {
                let cues = try await api.fetchPiliSubtitles(track)
                guard !Task.isCancelled, self.generation == token, self.selectionGeneration == selectionToken, self.selectedID == id else { return }
                self.cache[id] = cues
                self.timeline = SubtitleTimeline(cues)
            } catch {
                guard !Task.isCancelled, self.generation == token, self.selectionGeneration == selectionToken, self.selectedID == id else { return }
                self.errorMessage = error.localizedDescription
            }
        }
    }
    func importText(_ text: String, name: String) throws {
        let cues = SubtitleTextCodec.parse(text)
        guard !cues.isEmpty else { throw PiliOfflineError.message("未找到有效的 SRT 或 VTT 字幕") }
        let track = PiliSubtitleTrack(lan: "local-\(UUID().uuidString)", lanDoc: name, subtitleURL: nil, type: 0)
        tracks.append(track); cache[track.id] = cues
        select(track.id)
    }
    func export(vtt: Bool) throws -> URL {
        guard !timeline.cues.isEmpty else { throw PiliOfflineError.message("请先选择并加载字幕") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PiliSubtitleExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("subtitle-\(UUID().uuidString).\(vtt ? "vtt" : "srt")")
        let text = vtt ? SubtitleTextCodec.vtt(timeline.cues) : SubtitleTextCodec.srt(timeline.cues)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    func selectPreferred() {
        let mode = UserDefaults.standard.string(forKey: "piliplus.subtitle.mode") ?? "withoutAI"
        let preferred = UserDefaults.standard.string(forKey: "piliplus.subtitle.language")
        let candidates = mode == "withoutAI" ? tracks.filter { !$0.isAI } : tracks
        select(mode == "off" ? nil : (candidates.first { $0.lan == preferred } ?? candidates.first)?.id, remember: false)
    }
    private func reset() {
        selectionTask?.cancel(); selectionTask = nil; generation = UUID(); api = nil; contextID = nil
        selectedID = nil; tracks = []; cache = [:]; timeline = SubtitleTimeline([]); errorMessage = nil; isLoading = false
    }
    deinit { selectionTask?.cancel() }
}
