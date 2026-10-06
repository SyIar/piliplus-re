import Foundation
import PiliPlaybackCore

extension VideoDetailViewModel {
    /// Commit the graph transaction only after the destination presents a frame.
    func openPiliInteractivePage(cid: Int, title: String, automatic: Bool) async throws {
        let bvid = detail.bvid, sourceCID = selectedCID
        let version = api.requestSnapshot(purpose: .playback).playbackCredentialVersion
        let oldTime = stablePlayerViewModel?.currentTime ?? 0
        let oldIntent = currentPlaybackIntent()
        let data = try await api.fetchPlayURL(bvid: bvid, cid: cid)
        try Task.checkCancellation()
        guard !isPlaybackInvalidatedForNavigation, detail.bvid == bvid, selectedCID == sourceCID,
              api.requestSnapshot(purpose: .playback).playbackCredentialVersion == version else { throw CancellationError() }
        guard data.hasPlayableStreamPayload else { throw BiliAPIError.missingPayload }
        if automatic, PiliSleepTimer.shared.shouldStopAtPlaybackEnd() {
            throw BiliAPIError.api(code: -1, message: "定时停止已生效，点击重试可继续剧情")
        }
        piliInteractive.selectingInteractivePage {
            selectPage(VideoPage(cid: cid, page: nil, part: title, duration: nil, dimension: nil))
        }
        pendingVideoListenPlaybackIntent = true
        do {
            await pageLoadingTask?.value
            let deadline = ContinuousClock.now.advanced(by: .seconds(25))
            while ContinuousClock.now < deadline {
                try Task.checkCancellation()
                guard !isPlaybackInvalidatedForNavigation, detail.bvid == bvid, selectedCID == cid,
                      api.requestSnapshot(purpose: .playback).playbackCredentialVersion == version else { throw CancellationError() }
                if automatic, PiliSleepTimer.shared.policy.preventsAutomaticPlayback {
                    throw BiliAPIError.api(code: -1, message: "定时停止已生效，点击重试可继续剧情")
                }
                if case let .failed(message) = playURLState { throw BiliAPIError.api(code: -1, message: message) }
                if let message = stablePlayerViewModel?.errorMessage { throw BiliAPIError.api(code: -1, message: message) }
                if stablePlayerViewModel?.hasPresentedPlayback == true { return }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw BiliAPIError.api(code: -1, message: "互动分支播放启动超时，请重试")
        } catch {
            if !Task.isCancelled, !isPlaybackInvalidatedForNavigation, detail.bvid == bvid,
               selectedCID == cid, api.requestSnapshot(purpose: .playback).playbackCredentialVersion == version,
               let sourceCID {
                piliInteractive.selectingInteractivePage {
                    selectPage(VideoPage(cid: sourceCID, page: nil, part: nil, duration: nil, dimension: nil))
                }
                pendingVideoListenPlaybackIntent = oldIntent && !PiliSleepTimer.shared.policy.preventsAutomaticPlayback
                pendingPlaybackHistoryResumeCID = sourceCID
                pendingPlaybackHistoryResumeTime = oldTime
                await pageLoadingTask?.value
            }
            throw error
        }
    }
}
