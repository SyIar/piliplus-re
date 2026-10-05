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
        if playbackContentMode == .audioOnly {
            handleVideoListenPlaybackEnded()
            return
        }
        let order = PlaybackOrder(rawValue: UserDefaults.standard.string(forKey: "piliplus.playbackOrder") ?? "") ?? .sequential
        let pages = detail.pages ?? []
        let currentIndex = pages.firstIndex { $0.cid == selectedCID }
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
                      !PiliSleepTimer.shared.policy.preventsAutomaticPlayback
                else { return }
                self.switchPiliAutoplayVideo(fullDetail)
            } catch {
                guard !Task.isCancelled else { return }
                self.playbackFallbackMessage = "下一条视频加载失败：\(error.localizedDescription)"
            }
        }
        trackBackgroundTask(task)
    }

    private func switchPiliAutoplayVideo(_ video: VideoItem) {
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
