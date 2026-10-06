import Foundation
import PiliPlaybackCore

struct PiliCastQueueEntry: Identifiable {
    let id: String
    let title: String
    let resolve: @MainActor () async throws -> PiliCastSource
}
struct PiliCastQueuePlan {
    let entries: [PiliCastQueueEntry]
    let initialIndex: Int
    var loadMore: (@MainActor () async throws -> PiliCastQueuePlan)? = nil
}

extension PiliCastSource {
    static func onlineQueue(_ model: VideoDetailViewModel) -> @MainActor () async throws -> PiliCastQueuePlan {
        let seed = model.detail, currentCID = model.selectedCID, api = model.api
        let quality = model.selectedPlayVariant?.quality ?? 80
        let codec = model.selectedPlayVariant?.codec
        let explicitQueue = model.piliPlaybackQueue
        let version = api.requestSnapshot(purpose: .playback).playbackCredentialVersion
        return { try await onlinePlan(seed: seed, currentCID: currentCID, api: api, quality: quality, codec: codec,
            explicitQueue: explicitQueue, version: version) }
    }

    private static func onlinePlan(seed: VideoItem, currentCID: Int?, api: BiliAPIClient, quality: Int,
                                   codec: String?, explicitQueue: PiliPlaybackQueue?, version: Int) async throws -> PiliCastQueuePlan {
            var videos: [VideoItem]
            if let explicitQueue, explicitQueue.bvids.count > 1 || explicitQueue.nextPage != nil {
                videos = explicitQueue.placeholderVideos().map { $0.bvid == seed.bvid ? seed : $0 }
            } else if seed.isPGCEpisode {
                let season = try await api.fetchPgcSeasonInfo(seasonID: seed.pgcSeasonID, epID: seed.pgcEpisodeID, isCourse: seed.piliIsCourse)
                videos = season.allPlayableEpisodes.compactMap { $0.videoItem(in: season) }
            } else if let collection = seed.piliUGCSeason { videos = collection.videos(defaultOwner: seed.owner) }
            else { videos = [seed] }
            if videos.isEmpty { videos = [seed] }
            var entries: [PiliCastQueueEntry] = []
            for video in videos {
                let pages = video.bvid == seed.bvid ? (seed.pages ?? []) : (video.pages ?? [])
                let cids: [Int?] = pages.isEmpty ? [video.cid] : pages.map { Optional($0.cid) }
                for cid in cids {
                    let title = pages.count > 1 ? "\(video.title) · \(pages.first { $0.cid == cid }?.part ?? "分 P")" : video.title
                    let id = "\(video.bvid)|\(cid ?? 0)"
                    entries.append(PiliCastQueueEntry(id: id, title: title) {
                        try Task.checkCancellation()
                        guard api.requestSnapshot(purpose: .playback).playbackCredentialVersion == version else { throw PiliOfflineError.message("播放账号已切换，请重新投屏") }
                        let detail = cid != nil || video.isPGCEpisode ? video : try await api.fetchVideoDetail(bvid: video.bvid)
                        guard let resolvedCID = cid ?? detail.cid ?? detail.pages?.first?.cid else { throw BiliAPIError.missingPayload }
                        let data: PlayURLData
                        if detail.isPGCEpisode {
                            data = try await api.fetchPgcPlayURL(bvid: detail.bvid, cid: resolvedCID, seasonID: detail.pgcSeasonID,
                                epID: detail.pgcEpisodeID, preferredQuality: quality)
                        } else { data = try await api.fetchPlayURL(bvid: detail.bvid, cid: resolvedCID, preferredQuality: quality) }
                        let variants = data.playVariants.filter { $0.isPlayable && $0.audioURL != nil && $0.quality <= quality }
                        guard let variant = variants.first(where: { $0.quality == quality && $0.codec == codec }) ?? variants.first else {
                            throw PiliOfflineError.message("该视频没有设备可用的投屏音视频流")
                        }
                        let context = api.requestSnapshot(purpose: .playback)
                        guard context.playbackCredentialVersion == version else { throw PiliOfflineError.message("播放账号已切换，请重新投屏") }
                        return PiliCastSource(title: title, duration: Double(detail.pages?.first(where: { $0.cid == resolvedCID })?.duration ?? detail.duration ?? 0), position: 0, variant: variant, localFile: nil,
                            headers: BiliHLSManifestBuilder.httpHeaders(referer: "https://www.bilibili.com/", cookieHeader: context.cookieHeader))
                    })
                }
            }
            var seen = Set<String>(); entries = entries.filter { seen.insert($0.id).inserted }
            let index = entries.firstIndex { $0.id == "\(seed.bvid)|\(currentCID ?? 0)" }
                ?? entries.firstIndex { $0.id.hasPrefix(seed.bvid + "|") } ?? 0
            var plan = PiliCastQueuePlan(entries: entries, initialIndex: index)
            if let explicitQueue, explicitQueue.nextPage != nil {
                plan.loadMore = {
                    let expanded = try await expandedCastQueue(explicitQueue, api: api)
                    return try await onlinePlan(seed: seed, currentCID: currentCID, api: api, quality: quality,
                        codec: codec, explicitQueue: expanded, version: version)
                }
            }
            return plan
    }

    static func expandedCastQueue(_ initial: PiliPlaybackQueue, api: BiliAPIClient) async throws -> PiliPlaybackQueue {
        var queue = initial
        func check() throws {
            let current: Int
            switch queue.source {
            case .watchLater, .watchLaterFiltered: current = api.sessionStore.historyAccountCredentialVersion
            case .favoriteFolder: current = api.sessionStore.interactionAccountCredentialVersion
            case .ugcSeason, .collection: return
            }
            guard current == queue.credentialVersion else { throw PiliOfflineError.message("列表账号已切换，请重新投屏") }
        }
        let count = queue.bvids.count
        for _ in 0..<5 {
            try check(); try Task.checkCancellation()
            guard let page = queue.nextPage else { break }
            switch queue.source {
            case let .watchLaterFiltered(filter):
                let data = try await api.fetchPiliWatchLaterPage(page: page, filter: filter)
                queue.append(videos: data.entries.map(\.videoItem)); queue.nextPage = data.hasMore ? page + 1 : nil
            case let .favoriteFolder(id):
                let data = try await api.fetchFavoriteFolderVideoPage(folderID: id, page: page, pageSize: 20)
                queue.append(videos: data.entries.map(\.videoItem)); queue.nextPage = data.hasMore ? page + 1 : nil
            case let .collection(owner, kind, ascending, _):
                let data = try await api.fetchUploaderSeasonSeriesArchivePage(mid: owner.mid, owner: owner, kind: kind,
                    page: page, pageSize: 30, sort: ascending ? .asc : .desc)
                queue.append(videos: data.videos); queue.nextPage = data.hasMore ? page + 1 : nil
            case .watchLater, .ugcSeason: queue.nextPage = nil
            }
            try check(); try Task.checkCancellation()
            if queue.bvids.count > count { break }
        }
        if queue.bvids.count == count, queue.nextPage != nil { throw PiliOfflineError.message("后续页面暂时没有可播放内容，请重试加载") }
        return queue
    }

    static func offlineQueue(current: OfflineDownloadItem) -> PiliCastQueuePlan {
        let records = PiliOfflineStore.shared.items.filter { $0.state == .completed && $0.effectiveMediaKind == current.effectiveMediaKind }
        let entries = records.map { record in
            PiliCastQueueEntry(id: record.id.uuidString, title: record.title) {
                .init(title: record.title, duration: record.duration, position: 0, variant: nil,
                      localFile: try PiliOfflineStorage.playbackURL(record), headers: [:])
            }
        }
        return .init(entries: entries, initialIndex: records.firstIndex { $0.id == current.id } ?? 0)
    }
}
