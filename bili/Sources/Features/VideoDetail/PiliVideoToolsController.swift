import Combine
import Foundation

@MainActor
final class PiliVideoToolsController: ObservableObject {
    @Published private(set) var chapters: [PiliVideoChapter] = []
    @Published private(set) var staff: [PiliVideoStaff] = []
    @Published private(set) var tags: [PiliVideoTag] = []
    @Published private(set) var energy: PiliVideoEnergy?
    @Published private(set) var currentClip: PiliPGCClip?
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    private var context = ""
    private var loaded = false
    private var loadTask: Task<Void, Never>?
    deinit { loadTask?.cancel() }
    private var skipped = Set<String>()

    func load(_ model: VideoDetailViewModel) async {
        let video = model.detail
        guard let cid = model.selectedCID else { return }
        let account = model.api.requestSnapshot(purpose: .playback)
        let key = "\(video.bvid)|\(cid)|\(account.playbackCredentialVersion)"
        guard context != key || !loaded else { return }
        if context == key, let loadTask { await loadTask.value; return }
        loadTask?.cancel()
        if context != key { loaded = false; chapters = []; staff = []; tags = []; energy = nil; currentClip = nil; skipped = [] }
        context = key; loading = true; error = nil
        let task = Task { [weak self, weak model] in
            guard let self, let model else { return }
            await self.performLoad(model, key: key, cid: cid, version: account.playbackCredentialVersion)
        }
        loadTask = task
        await task.value
    }
    private func performLoad(_ model: VideoDetailViewModel, key: String, cid: Int, version: Int) async {
        defer { if context == key { loading = false; loadTask = nil } }
        let api = model.api, video = model.detail
        guard !video.piliIsCourse else { loaded = true; return }
        // Optional metadata loads do not delay the video or fail playback.
        async let chapterResult = try? api.piliVideoChapters(bvid: video.bvid, cid: cid, seasonID: video.pgcSeasonID, episodeID: video.pgcEpisodeID)
        async let staffResult = try? api.piliVideoCredits(bvid: video.bvid)
        async let tagResult = try? api.piliVideoTags(bvid: video.bvid)
        async let energyResult = try? api.piliVideoEnergy(bvid: video.bvid, aid: video.aid ?? 0, cid: cid)
        let (c, s, t, e) = await (chapterResult, staffResult, tagResult, energyResult)
        guard !Task.isCancelled, context == key, model.api.requestSnapshot(purpose: .playback).playbackCredentialVersion == version else { return }
        chapters = c ?? []; staff = s ?? []; tags = t ?? []; energy = e
        loaded = true
        if c == nil && s == nil && t == nil && e == nil { error = "附加信息暂时不可用"; loaded = false }
    }
    func tick(_ time: Double, model: VideoDetailViewModel) {
        let clip = model.currentPlayURLData?.clipInfoList?.first { $0.isValid && time >= $0.start && time < $0.end }
        if currentClip != clip { currentClip = clip }
        guard UserDefaults.standard.bool(forKey: "piliplus.player.skipPGC"), let clip,
              !skipped.contains(clip.id), model.stablePlayerViewModel?.isPlaying == true else { return }
        skip(clip, model: model)
    }
    func skip(_ clip: PiliPGCClip, model: VideoDetailViewModel) {
        guard let player = model.stablePlayerViewModel, !player.isTerminated,
              !PiliSleepTimer.shared.shouldStopAtPlaybackEnd(), let duration = player.duration, duration > 0,
              clip.isValid, clip.end <= duration + 1 else { return }
        skipped.insert(clip.id)
        player.seek(to: min(clip.end, duration))
    }
    func retry(_ model: VideoDetailViewModel) async { loaded = false; await load(model) }
}
