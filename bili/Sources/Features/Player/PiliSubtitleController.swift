import Combine
import Foundation
import PiliPlaybackCore

@MainActor
final class PiliSubtitleController: ObservableObject {
    @Published private(set) var tracks: [PiliSubtitleTrack] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var secondaryID: String?
    @Published private(set) var timeline = SubtitleTimeline([])
    @Published private(set) var secondaryTimeline = SubtitleTimeline([])
    @Published private(set) var dualEnabled: Bool
    @Published private(set) var isLoading = false
    @Published private(set) var isSecondaryLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var secondaryError: String?
    private let defaults: UserDefaults
    private var cache: [String: [SubtitleCue]] = [:]
    private var selectionGeneration = UUID()
    private var secondaryGeneration = UUID()
    private var selectionTask: Task<Void, Never>?
    private var secondaryTask: Task<Void, Never>?
    private var contextID: String?
    private var generation = UUID()
    private var api: BiliAPIClient?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dualEnabled = defaults.bool(forKey: "piliplus.subtitle.dualEnabled")
    }

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
            let values = try await api.fetchPiliSubtitleTracks(bvid: video.bvid, aid: video.aid, cid: cid,
                                                                seasonID: video.pgcSeasonID, episodeID: video.pgcEpisodeID)
            guard !Task.isCancelled, generation == token else { return }
            var seen = Set<String>()
            tracks = values.filter { seen.insert($0.id).inserted }.sorted {
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
        var seen = Set<String>()
        tracks = values.map(\.track).filter { seen.insert($0.id).inserted }
        cache = Dictionary(values.map { ($0.track.id, $0.cues) }, uniquingKeysWith: { first, _ in first })
        selectPreferred()
    }

    func select(_ id: String?, remember: Bool = true) {
        let validID = tracks.first { $0.id == id }?.id
        if remember {
            defaults.set(validID == nil ? "off" : "on", forKey: "piliplus.subtitle.mode")
            if let track = tracks.first(where: { $0.id == validID }) { defaults.set(track.lan, forKey: "piliplus.subtitle.language") }
        }
        loadSelection(validID, secondary: false)
        if validID == nil { loadSelection(nil, secondary: true) }
        else if dualEnabled && (secondaryID == nil || secondaryID == validID) { selectPreferredSecondary() }
    }

    func setDualEnabled(_ enabled: Bool) {
        dualEnabled = enabled
        defaults.set(enabled, forKey: "piliplus.subtitle.dualEnabled")
        if enabled { selectPreferredSecondary() } else { loadSelection(nil, secondary: true) }
    }

    func selectSecondary(_ id: String?) {
        guard selectedID != nil, let track = tracks.first(where: { $0.id == id }), track.id != selectedID else {
            loadSelection(nil, secondary: true)
            return
        }
        dualEnabled = true
        defaults.set(true, forKey: "piliplus.subtitle.dualEnabled")
        defaults.set(track.lan, forKey: "piliplus.subtitle.secondaryLanguage")
        loadSelection(track.id, secondary: true)
    }

    private func selectPreferredSecondary() {
        let preferred = defaults.string(forKey: "piliplus.subtitle.secondaryLanguage")
        let candidates = tracks.filter { $0.id != selectedID && ((defaults.string(forKey: "piliplus.subtitle.mode") ?? "withoutAI") != "withoutAI" || !$0.isAI) }
        let id = selectedID == nil ? nil : (candidates.first { $0.lan == preferred } ?? candidates.first)?.id
        loadSelection(id, secondary: true)
    }

    /// Each slot owns its cancellation token. Switching languages or videos cannot install an old response.
    private func loadSelection(_ id: String?, secondary: Bool) {
        let selectionToken = UUID()
        if secondary {
            secondaryTask?.cancel(); secondaryTask = nil; secondaryGeneration = selectionToken
            secondaryID = id; secondaryTimeline = SubtitleTimeline([]); secondaryError = nil; isSecondaryLoading = false
        } else {
            selectionTask?.cancel(); selectionTask = nil; selectionGeneration = selectionToken
            selectedID = id; timeline = SubtitleTimeline([]); errorMessage = nil; isLoading = false
        }
        guard let id else { return }
        if let cues = cache[id] {
            if secondary { secondaryTimeline = SubtitleTimeline(cues) } else { timeline = SubtitleTimeline(cues) }
            return
        }
        guard let api, let track = tracks.first(where: { $0.id == id }) else { return }
        let token = generation
        if secondary { isSecondaryLoading = true } else { isLoading = true }
        let task = Task { [weak self] in
            guard let self else { return }
            @MainActor func isCurrent() -> Bool {
                self.generation == token && (secondary ? self.secondaryGeneration : self.selectionGeneration) == selectionToken
            }
            defer {
                if isCurrent() {
                    if secondary { self.isSecondaryLoading = false; self.secondaryTask = nil }
                    else { self.isLoading = false; self.selectionTask = nil }
                }
            }
            do {
                let cues = try await api.fetchPiliSubtitles(track)
                guard !Task.isCancelled, isCurrent() else { return }
                self.cache[id] = cues
                if secondary { self.secondaryTimeline = SubtitleTimeline(cues) } else { self.timeline = SubtitleTimeline(cues) }
            } catch {
                guard !Task.isCancelled, isCurrent() else { return }
                if secondary { self.secondaryError = error.localizedDescription } else { self.errorMessage = error.localizedDescription }
            }
        }
        if secondary { secondaryTask = task } else { selectionTask = task }
    }

    func importText(_ text: String, name: String) throws {
        let cues = SubtitleTextCodec.parse(text)
        guard !cues.isEmpty else { throw PiliOfflineError.message("未找到有效的 SRT 或 VTT 字幕") }
        let track = PiliSubtitleTrack(lan: "local-\(UUID().uuidString)", lanDoc: name, subtitleURL: nil, type: 0)
        tracks.append(track); cache[track.id] = cues
        select(track.id)
    }
    func export(vtt: Bool, secondary: Bool = false) throws -> URL {
        let cues = secondary ? secondaryTimeline.cues : timeline.cues
        guard !cues.isEmpty else { throw PiliOfflineError.message("请先选择并加载字幕") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PiliSubtitleExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("subtitle-\(UUID().uuidString).\(vtt ? "vtt" : "srt")")
        let text = vtt ? SubtitleTextCodec.vtt(cues) : SubtitleTextCodec.srt(cues)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    func selectPreferred() {
        let mode = defaults.string(forKey: "piliplus.subtitle.mode") ?? "withoutAI"
        let preferred = defaults.string(forKey: "piliplus.subtitle.language")
        let candidates = mode == "withoutAI" ? tracks.filter { !$0.isAI } : tracks
        select(mode == "off" ? nil : (candidates.first { $0.lan == preferred } ?? candidates.first)?.id, remember: false)
        if dualEnabled { selectPreferredSecondary() }
    }
    private func reset() {
        selectionTask?.cancel(); selectionTask = nil; secondaryTask?.cancel(); secondaryTask = nil
        generation = UUID(); api = nil; contextID = nil
        selectedID = nil; secondaryID = nil; tracks = []; cache = [:]
        timeline = SubtitleTimeline([]); secondaryTimeline = SubtitleTimeline([])
        errorMessage = nil; secondaryError = nil; isLoading = false; isSecondaryLoading = false
    }
    deinit { selectionTask?.cancel(); secondaryTask?.cancel() }
}
