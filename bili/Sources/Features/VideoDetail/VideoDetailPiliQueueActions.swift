import Foundation
import PiliPlaybackCore

extension VideoDetailViewModel {
    func loadPiliNextQueueVideo(order: PlaybackOrder) {
        guard var queue = piliPlaybackQueue, !isAdvancingPiliQueue else { return }
        guard isPiliQueueAccountCurrent(queue) else {
            stablePlayerViewModel?.pause()
            playbackFallbackMessage = "账号已切换，请重新打开播放列表"
            return
        }
        let sourceBVID = detail.bvid
        let sourceCID = selectedCID
        isAdvancingPiliQueue = true
        let task = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer { self.isAdvancingPiliQueue = false }
            do {
                // Only fetch another favorite page at its boundary, preserving the list order.
                if queue.bvids.last == sourceBVID,
                   case let .favoriteFolder(folderID) = queue.source,
                   let page = queue.nextPage {
                    let result = try await self.api.fetchFavoriteFolderVideoPage(folderID: folderID, page: page, pageSize: 20)
                    let previousCount = queue.bvids.count
                    queue.append(result.entries.map(\.bvid))
                    queue.nextPage = result.hasMore && queue.bvids.count > previousCount ? page + 1 : nil
                }
                guard self.canAdvancePiliQueue(queue, bvid: sourceBVID, cid: sourceCID) else { return }
                self.piliPlaybackQueue = queue
                let action = PlaybackEndPolicy.resolve(
                    order: order,
                    currentIndex: queue.bvids.firstIndex(of: sourceBVID),
                    count: queue.bvids.count,
                    sleepTimerStops: false
                )
                switch action {
                case let .advance(index):
                    let next = try await self.fetchFullDetail(identity: .bvid(queue.bvids[index]), priority: .userInitiated)
                    guard self.canAdvancePiliQueue(queue, bvid: sourceBVID, cid: sourceCID) else { return }
                    self.switchPiliAutoplayVideo(next.withPiliPlaybackQueue(queue))
                case .replay:
                    // A single-video playlist repeats from its first part.
                    if let first = self.detail.pages?.first, first.cid != self.selectedCID {
                        self.selectPage(first)
                    } else {
                        self.stablePlayerViewModel?.seek(to: 0)
                        self.stablePlayerViewModel?.play()
                    }
                case .stop, .loadRelated:
                    // Explicit account lists stop at their boundary unless list repeat is selected.
                    self.stablePlayerViewModel?.pause()
                }
            } catch {
                guard !Task.isCancelled,
                      self.isCurrentPlaybackContext(bvid: sourceBVID, cid: sourceCID)
                else { return }
                self.playbackFallbackMessage = "播放列表加载失败：\(error.localizedDescription)"
            }
        }
        trackBackgroundTask(task)
    }

    private func isPiliQueueAccountCurrent(_ queue: PiliPlaybackQueue) -> Bool {
        switch queue.source {
        case .watchLater: sessionStore.historyAccountCredentialVersion == queue.credentialVersion
        case .favoriteFolder: sessionStore.interactionAccountCredentialVersion == queue.credentialVersion
        }
    }

    private func canAdvancePiliQueue(_ queue: PiliPlaybackQueue, bvid: String, cid: Int?) -> Bool {
        !Task.isCancelled && !isPlaybackInvalidatedForNavigation && playbackContentMode == .video
            && isCurrentPlaybackContext(bvid: bvid, cid: cid)
            && isPiliQueueAccountCurrent(queue)
            && !PiliSleepTimer.shared.shouldStopAtPlaybackEnd()
    }
}
