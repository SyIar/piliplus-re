import Combine
import Foundation
import PiliPlaybackCore

enum PiliBatchDownloadSource {
    case selected([VideoItem])
    case favorite(id: Int, keyword: String, order: PiliFavoriteOrder)
    case watchLater(PiliWatchLaterFilter)
}

struct PiliBatchDownloadRequest: Identifiable {
    let id = UUID()
    let source: PiliBatchDownloadSource
    let title: String
    let purpose: BiliAccountPurpose
    let credentialVersion: Int
}

@MainActor
protocol PiliOfflineEnqueuing {
    func enqueue(video: VideoItem, pages: [VideoPage], variant: PlayVariant) throws -> Int
    func enqueueAudio(video: VideoItem, pages: [VideoPage], audio: VideoListenAudioVariant) throws -> Int
}
extension PiliOfflineStore: PiliOfflineEnqueuing {}

enum PiliBatchDownloadPlanner {
    static func pages(for video: VideoItem, allParts: Bool) -> [VideoPage] {
        var seen = Set<Int>()
        let pages = (video.pages ?? []).filter { $0.cid > 0 && seen.insert($0.cid).inserted }
        if !pages.isEmpty { return allParts ? pages : Array(pages.prefix(1)) }
        guard let cid = video.cid, cid > 0 else { return [] }
        return [VideoPage(cid: cid, page: 1, part: video.title, duration: video.duration, dimension: video.dimension)]
    }

    static func variant(in data: PlayURLData, maximumQuality: Int) -> PlayVariant? {
        data.playVariants.filter { $0.isPlayable && $0.quality <= maximumQuality }
            .sorted { $0.quality > $1.quality }.first
    }
}

@MainActor
final class PiliBatchDownloadModel: ObservableObject {
    let api: BiliAPIClient
    let request: PiliBatchDownloadRequest
    private let downloads: any PiliOfflineEnqueuing
    @Published var mediaKind = OfflineMediaKind.video
    @Published var maximumQuality = 80
    @Published var allParts = true
    @Published private(set) var isRunning = false
    @Published private(set) var hasFinished = false
    @Published private(set) var status = "选择下载内容后开始"
    @Published private(set) var addedCount = 0
    @Published private(set) var duplicateCount = 0
    @Published private(set) var failures: [String] = []
    @Published private(set) var processed = 0
    @Published private(set) var total = 0
    private var task: Task<Void, Never>?

    init(api: BiliAPIClient, request: PiliBatchDownloadRequest, downloads: (any PiliOfflineEnqueuing)? = nil) {
        self.api = api; self.request = request; self.downloads = downloads ?? PiliOfflineStore.shared
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true; hasFinished = false; addedCount = 0; duplicateCount = 0
        failures = []; processed = 0; total = 0
        let kind = mediaKind, quality = maximumQuality, includeAll = allParts
        let playbackVersion = api.requestSnapshot(purpose: .playback).playbackCredentialVersion
        let mainVersion = api.requestSnapshot(purpose: .main).playbackCredentialVersion
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.isRunning = false; self.hasFinished = true; self.task = nil }
            @MainActor func check() throws {
                try Task.checkCancellation()
                guard self.api.requestSnapshot(purpose: self.request.purpose).playbackCredentialVersion == self.request.credentialVersion,
                      self.api.requestSnapshot(purpose: .playback).playbackCredentialVersion == playbackVersion,
                      self.api.requestSnapshot(purpose: .main).playbackCredentialVersion == mainVersion else {
                    throw PiliOfflineError.message("账号已切换，已停止添加；已入队的任务可在离线下载中管理")
                }
            }
            do {
                try check()
                let videos = try await self.loadVideos(check: check)
                self.total = videos.count
                for seed in videos {
                    try check()
                    self.status = "\(self.processed + 1)/\(self.total) · \(seed.title)"
                    do {
                        let video = seed.pgcEpisodeID != nil || seed.pgcSeasonID != nil
                            ? seed : try await self.api.fetchVideoDetail(bvid: seed.bvid)
                        try check()
                        let pages = PiliBatchDownloadPlanner.pages(for: video, allParts: includeAll)
                        guard !pages.isEmpty else { throw PiliOfflineError.message("视频已失效或没有可下载分集") }
                        for page in pages {
                            try check()
                            do {
                                let data: PlayURLData
                                if video.pgcEpisodeID != nil || video.pgcSeasonID != nil {
                                    data = try await self.api.fetchPgcPlayURL(bvid: video.bvid, cid: page.cid,
                                        seasonID: video.pgcSeasonID, epID: video.pgcEpisodeID, preferredQuality: kind == .audio ? 64 : quality)
                                } else {
                                    data = try await self.api.fetchPlayURLUncached(bvid: video.bvid, cid: page.cid,
                                        preferredQuality: kind == .audio ? 64 : quality)
                                }
                                try check()
                                let count: Int
                                if kind == .audio {
                                    let audios = data.videoListenAudioVariants(cdnPreference: .automatic)
                                    guard let audio = audios.first(where: { $0.stream == data.dash?.preferredAudioStream(self.api.libraryStore.effectiveAudioQualityPreference) }) ?? audios.first else {
                                        throw PiliOfflineError.message("没有独立音频流或当前账号无权下载")
                                    }
                                    count = try self.downloads.enqueueAudio(video: video, pages: [page], audio: audio)
                                } else {
                                    guard let variant = PiliBatchDownloadPlanner.variant(in: data, maximumQuality: quality) else {
                                        throw PiliOfflineError.message("没有所选范围内的可下载画质")
                                    }
                                    count = try self.downloads.enqueue(video: video, pages: [page], variant: variant)
                                }
                                self.addedCount += count
                                if count == 0 { self.duplicateCount += 1 }
                            } catch {
                                try check()
                                self.failures.append("\(seed.title) · \(page.part ?? "分集")：\(error.localizedDescription)")
                            }
                        }
                    } catch {
                        try check()
                        self.failures.append("\(seed.title)：\(error.localizedDescription)")
                    }
                    self.processed += 1
                }
                self.status = videos.isEmpty ? "没有匹配的视频" : "批量添加完成"
            } catch is CancellationError {
                self.status = "已停止添加；已入队的任务仍保留"
            } catch {
                self.status = error.localizedDescription
            }
        }
    }

    func cancel() { task?.cancel() }
    func waitUntilFinished() async { await task?.value }

    private func loadVideos(check: @MainActor () throws -> Void) async throws -> [VideoItem] {
        if case let .selected(videos) = request.source {
            var seen = Set<String>()
            return videos.filter { !$0.bvid.isEmpty && seen.insert($0.bvid).inserted }
        }
        var videos: [VideoItem] = []
        var seen = Set<String>()
        var lastPageIDs: [String]?
        for page in 1...1000 {
            try check()
            status = "正在读取第 \(page) 页，已找到 \(videos.count) 个视频"
            let result: AccountVideoEntryPage
            switch request.source {
            case let .favorite(id, keyword, order):
                result = try await api.fetchPiliFavoriteItems(folderID: id, page: page, keyword: keyword, order: order)
            case let .watchLater(filter): result = try await api.fetchPiliWatchLaterPage(page: page, filter: filter)
            case .selected: return videos
            }
            try check()
            let ids = result.entries.map(\.bvid)
            if !ids.isEmpty, ids == lastPageIDs, result.hasMore {
                throw PiliOfflineError.message("服务器重复返回同一页，请稍后重试")
            }
            lastPageIDs = ids
            videos.append(contentsOf: result.entries.map(\.videoItem).filter { !$0.bvid.isEmpty && seen.insert($0.bvid).inserted })
            if !result.hasMore { return videos }
        }
        throw PiliOfflineError.message("列表过大，请缩小搜索范围后再批量下载")
    }
    deinit { task?.cancel() }
}
