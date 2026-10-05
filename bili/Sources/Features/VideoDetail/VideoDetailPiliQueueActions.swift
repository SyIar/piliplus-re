import Foundation
import PiliPlaybackCore

extension VideoDetailViewModel {
    func seedPiliCollectionQueueIfNeeded() {
        guard piliPlaybackQueue == nil, let season = detail.piliUGCSeason else { return }
        let videos = season.videos(defaultOwner: detail.owner)
        guard videos.count > 1, videos.contains(where: { $0.bvid == detail.bvid }) else { return }
        var queue = PiliPlaybackQueue(source: .ugcSeason(id: season.id ?? 0, title: season.title ?? "视频合集"),
                                      credentialVersion: 0, bvids: [], nextPage: nil)
        queue.append(videos: videos)
        piliPlaybackQueue = queue
    }

    func loadPiliNextQueueVideo(order: PlaybackOrder) {
        advancePiliQueue(direction: .next, automatic: true, order: order)
    }

    func advancePiliQueue(direction: VideoListenAdvanceDirection, automatic: Bool, order: PlaybackOrder? = nil) {
        guard let initial = piliPlaybackQueue, !isAdvancingPiliQueue else { return }
        if !automatic { PiliSleepTimer.shared.resumeManually() }
        let order = order ?? PiliPlaybackPreferences.shared.order
        let sourceBVID = detail.bvid, sourceCID = selectedCID
        isAdvancingPiliQueue = true
        let task = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer { self.isAdvancingPiliQueue = false }
            do {
                guard self.canAdvancePiliQueue(initial, bvid: sourceBVID, cid: sourceCID) else { return }
                let queue = direction == .next ? try await self.expandedPiliQueue(initial, at: sourceBVID) : initial
                guard self.canAdvancePiliQueue(queue, bvid: sourceBVID, cid: sourceCID) else { return }
                self.piliPlaybackQueue = queue
                self.syncPiliListenQueue(queue)
                guard let current = queue.bvids.firstIndex(of: sourceBVID) else { return }
                let target: Int?
                if direction == .previous { target = current > 0 ? current - 1 : nil }
                else if automatic {
                    switch PlaybackEndPolicy.resolve(order: order, currentIndex: current, count: queue.bvids.count, sleepTimerStops: false) {
                    case let .advance(index): target = index
                    case .replay: target = current
                    case .stop, .loadRelated: target = nil
                    }
                } else { target = current + 1 < queue.bvids.count ? current + 1 : nil }
                guard let target else {
                    if direction == .previous { self.stablePlayerViewModel?.seek(to: 0) }
                    else { self.stablePlayerViewModel?.pause() }
                    return
                }
                if queue.bvids[target] == sourceBVID {
                    if let page = self.detail.pages?.first, page.cid != self.selectedCID { self.selectPage(page) }
                    else { self.stablePlayerViewModel?.seek(to: 0); self.stablePlayerViewModel?.play() }
                    return
                }
                let next = try await self.fetchFullDetail(identity: .bvid(queue.bvids[target]), priority: .userInitiated)
                guard self.canAdvancePiliQueue(queue, bvid: sourceBVID, cid: sourceCID) else { return }
                self.switchPiliAutoplayVideo(next.withPiliPlaybackQueue(queue), startingFromLastPage: direction == .previous)
            } catch {
                guard !Task.isCancelled, self.isCurrentPlaybackContext(bvid: sourceBVID, cid: sourceCID) else { return }
                self.playbackFallbackMessage = "播放列表加载失败：\(error.localizedDescription)"
            }
        }
        trackBackgroundTask(task)
    }

    func selectPiliQueueVideo(bvid: String) {
        guard let queue = piliPlaybackQueue, queue.bvids.contains(bvid), !isAdvancingPiliQueue else { return }
        PiliSleepTimer.shared.resumeManually()
        if bvid == detail.bvid { return }
        let sourceBVID = detail.bvid, sourceCID = selectedCID
        isAdvancingPiliQueue = true
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.isAdvancingPiliQueue = false }
            do {
                guard self.canAdvancePiliQueue(queue, bvid: sourceBVID, cid: sourceCID) else { return }
                let next = try await self.fetchFullDetail(identity: .bvid(bvid), priority: .userInitiated)
                guard self.canAdvancePiliQueue(queue, bvid: sourceBVID, cid: sourceCID) else { return }
                self.switchPiliAutoplayVideo(next.withPiliPlaybackQueue(queue))
            } catch {
                guard !Task.isCancelled, self.isCurrentPlaybackContext(bvid: sourceBVID, cid: sourceCID) else { return }
                self.playbackFallbackMessage = error.localizedDescription
            }
        }
        trackBackgroundTask(task)
    }

    func loadMorePiliListenQueue() async {
        guard let queue = piliPlaybackQueue, queue.nextPage != nil, !isAdvancingPiliQueue else { return }
        let sourceBVID = detail.bvid, sourceCID = selectedCID
        isAdvancingPiliQueue = true
        defer { isAdvancingPiliQueue = false }
        do {
            let expanded = try await expandedPiliQueue(queue, at: queue.bvids.last ?? sourceBVID)
            guard !Task.isCancelled, isCurrentPlaybackContext(bvid: sourceBVID, cid: sourceCID), isPiliQueueAccountCurrent(expanded) else { return }
            piliPlaybackQueue = expanded
            syncPiliListenQueue(expanded)
        } catch { if !Task.isCancelled { playbackFallbackMessage = error.localizedDescription } }
    }

    func syncPiliListenQueue(_ queue: PiliPlaybackQueue) {
        guard playbackContentMode == .audioOnly else { return }
        let source = VideoListenQueueSource.pili(queue.source)
        var videos = queue.placeholderVideos()
        if let index = videos.firstIndex(where: { $0.bvid == detail.bvid }) { videos[index] = detail }
        let token = videoListenQueueSession.beginInitialLoad(source: source, anchor: detail)
        _ = videoListenQueueSession.finishInitialLoad(videos: videos, anchor: detail, source: source,
                                                      nextPage: max(1, (queue.nextPage ?? 2) - 1), nextCursor: nil,
                                                      hasMore: queue.nextPage != nil, generation: token)
        updateVideoListenRemoteNavigationAvailability()
    }

    private func expandedPiliQueue(_ initial: PiliPlaybackQueue, at bvid: String) async throws -> PiliPlaybackQueue {
        var queue = initial
        guard queue.bvids.last == bvid else { return queue }
        // A page can contain only invalid/deleted videos. Advance its cursor without
        // wrapping the list early, while bounding work for a single end callback.
        for _ in 0..<5 {
            guard let page = queue.nextPage else { break }
            guard isPiliQueueAccountCurrent(queue) else { throw PiliOfflineError.message("账号已切换，请重新打开播放列表") }
            switch queue.source {
            case let .watchLaterFiltered(filter):
                let result = try await api.fetchPiliWatchLaterPage(page: page, filter: filter)
                queue.append(videos: result.entries.map(\.videoItem))
                queue.nextPage = result.hasMore ? page + 1 : nil
            case let .favoriteFolder(folderID):
                let result = try await api.fetchFavoriteFolderVideoPage(folderID: folderID, page: page, pageSize: 20)
                queue.append(result.entries.map(\.bvid))
                queue.nextPage = result.hasMore ? page + 1 : nil
            case let .collection(owner, kind, ascending, _):
                let result = try await api.fetchUploaderSeasonSeriesArchivePage(mid: owner.mid, owner: owner, kind: kind,
                                                                                page: page, pageSize: 30, sort: ascending ? .asc : .desc)
                queue.append(videos: result.videos)
                queue.nextPage = result.hasMore ? page + 1 : nil
            case .watchLater, .ugcSeason:
                queue.nextPage = nil
            }
            try Task.checkCancellation()
            if queue.bvids.last != bvid { break }
        }
        if queue.bvids.last == bvid, queue.nextPage != nil {
            throw PiliOfflineError.message("后续页面暂无可播放内容，请打开列表继续加载")
        }
        return queue
    }

    private func isPiliQueueAccountCurrent(_ queue: PiliPlaybackQueue) -> Bool {
        switch queue.source {
        case .watchLater, .watchLaterFiltered: sessionStore.historyAccountCredentialVersion == queue.credentialVersion
        case .favoriteFolder: sessionStore.interactionAccountCredentialVersion == queue.credentialVersion
        case .ugcSeason, .collection: true
        }
    }
    private func canAdvancePiliQueue(_ queue: PiliPlaybackQueue, bvid: String, cid: Int?) -> Bool {
        if !isPiliQueueAccountCurrent(queue) {
            stablePlayerViewModel?.pause(); playbackFallbackMessage = "账号已切换，请重新打开播放列表"; return false
        }
        return !Task.isCancelled && !isPlaybackInvalidatedForNavigation
            && isCurrentPlaybackContext(bvid: bvid, cid: cid)
            && !PiliSleepTimer.shared.shouldStopAtPlaybackEnd()
    }
}
