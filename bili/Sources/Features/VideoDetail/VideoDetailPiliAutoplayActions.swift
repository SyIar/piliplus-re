import Foundation
import PiliPlaybackCore

extension VideoDetailViewModel {
    func handlePiliPlaybackEnded() {
        guard !isPlaybackInvalidatedForNavigation else { return }
        if PiliSleepTimer.shared.shouldStopAtPlaybackEnd() {
            cancelVideoListenSleepTimer()
            stablePlayerViewModel?.pause()
            return
        }
        if piliInteractive.handlePlaybackEnded() {
            stablePlayerViewModel?.pause()
            return
        }
        if playbackContentMode == .audioOnly {
            handleVideoListenPlaybackEnded()
            return
        }
        let order = PlaybackOrder(rawValue: UserDefaults.standard.string(forKey: "piliplus.playbackOrder") ?? "") ?? .sequential
        let pages = detail.pages ?? []
        let currentIndex = pages.firstIndex { $0.cid == selectedCID }
        let hasNextPage = currentIndex.map { $0 + 1 < pages.count } ?? false
        if piliPlaybackQueue != nil, !hasNextPage, order != .stop, order != .repeatOne {
            loadPiliNextQueueVideo(order: order)
            return
        }
        if detail.isPGCEpisode, order != .stop, order != .repeatOne {
            loadPiliNextPgcEpisode(order: order)
            return
        }
        let action = PlaybackEndPolicy.resolve(
            order: order, currentIndex: currentIndex, count: pages.count, sleepTimerStops: false
        )
        switch action {
        case .stop:
            stablePlayerViewModel?.pause()
        case .replay:
            stablePlayerViewModel?.seek(to: 0)
            stablePlayerViewModel?.play()
        case let .advance(index):
            selectPage(pages[index])
        case .loadRelated:
            loadPiliRelatedAutoplay()
        }
    }

    private func loadPiliNextPgcEpisode(order: PlaybackOrder) {
        let source = detail
        let sourceCID = selectedCID
        let task = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let season = try await self.api.fetchPgcSeasonInfo(
                    seasonID: source.pgcSeasonID, epID: source.pgcEpisodeID
                )
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.isCurrentPlaybackContext(bvid: source.bvid, cid: sourceCID),
                      !PiliSleepTimer.shared.shouldStopAtPlaybackEnd()
                else { return }
                let videos = season.selectableEpisodes.compactMap { $0.videoItem(in: season) }
                let index = videos.firstIndex {
                    ($0.pgcEpisodeID != nil && $0.pgcEpisodeID == source.pgcEpisodeID)
                        || ($0.bvid == source.bvid && $0.cid == sourceCID)
                }
                switch PlaybackEndPolicy.resolve(order: order, currentIndex: index, count: videos.count, sleepTimerStops: false) {
                case let .advance(next):
                    self.selectPgcEpisode(videos[next])
                case .replay:
                    self.stablePlayerViewModel?.seek(to: 0)
                    self.stablePlayerViewModel?.play()
                case .stop, .loadRelated:
                    self.stablePlayerViewModel?.pause()
                }
            } catch {
                guard !Task.isCancelled,
                      self.isCurrentPlaybackContext(bvid: source.bvid, cid: sourceCID)
                else { return }
                self.playbackFallbackMessage = "下一集加载失败：\(error.localizedDescription)"
            }
        }
        trackBackgroundTask(task)
    }

    private func loadPiliRelatedAutoplay() {
        let sourceBVID = detail.bvid
        let sourceCID = selectedCID
        let task = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let candidates = self.related.isEmpty
                    ? try await self.api.fetchVideoRelated(bvid: sourceBVID)
                    : self.related
                guard let next = candidates.first(where: { $0.bvid != sourceBVID }) else { return }
                let fullDetail = try await self.fetchFullDetail(identity: .bvid(next.bvid), priority: .userInitiated)
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.isCurrentPlaybackContext(bvid: sourceBVID, cid: sourceCID),
                      !PiliSleepTimer.shared.shouldStopAtPlaybackEnd()
                else { return }
                self.switchPiliAutoplayVideo(fullDetail)
            } catch {
                guard !Task.isCancelled else { return }
                self.playbackFallbackMessage = "下一条视频加载失败：\(error.localizedDescription)"
            }
        }
        trackBackgroundTask(task)
    }

    func switchPiliAutoplayVideo(_ video: VideoItem) {
        saveCurrentPlaybackProgressBeforeContentSwitch()
        cancelBackgroundTasks()
        detail = video
        selectedCID = video.cid ?? video.pages?.first?.cid
        hasResolvedDetailMetadata = true
        manuallySelectedPageCID = nil
        didResolveCloudHistoryResume = true
        pendingPlaybackHistoryResumeTime = nil
        pendingPlaybackHistoryResumeCID = nil
        resumeDiagnostics = .none
        resetPlaybackStateForSelectedPage()
        resetInlineStateForContentSwitch()
        state = .loaded
        syncCommentsRenderStore()
        syncRelatedRenderStore()
        scheduleRelatedLoadIfNeeded()
        scheduleUploaderAndInteractionLoadIfNeeded()
        beginInitialCommentsLoadIfNeeded(waitForPlaybackStart: false)
        pageLoadingTask?.cancel()
        let token = UUID()
        pageLoadingToken = token
        pageLoadingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer { self.clearPageLoadingTaskIfCurrent(token) }
            guard !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.pageLoadingToken == token,
                  !PiliSleepTimer.shared.policy.preventsAutomaticPlayback
            else { return }
            await self.loadPlayURL()
        }
    }
}
