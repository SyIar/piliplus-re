import Foundation

extension HomeViewModel {
    func replaceVideos(
        _ newVideos: [VideoItem],
        previousVideos: [VideoItem],
        preservingExistingRecommendations shouldPreserveExistingRecommendations: Bool = false
    ) {
        let mergedFeed = HomeFeedMergePolicy.refreshedFeed(
            fresh: newVideos,
            previousVideos: previousVideos,
            mode: mode,
            preservesExistingRecommendations: shouldPreserveExistingRecommendations,
            usesNativeReplacement: pageCoordinator.usesNativeAppRecommendSource(for: mode)
        )
        updateFeed(mergedFeed.videos, lastSeenMarkerIndex: mergedFeed.lastSeenMarkerIndex)
        exposureRecorder.recordIfNeeded(videos, mode: mode)
        Task {
            await ResourceLoadingForegroundPriorityGate.shared.beginFirstScreenPriorityWindow(for: .home)
        }
        mediaPreloadCoordinator.scheduleImagePrefetch(for: videos)
        mediaPreloadCoordinator.schedulePlaybackPreload(for: pageCoordinator.filterFeedRecommendations(newVideos), initialDelay: 0.75)
        scheduleRecommendMetadataHydration(
            for: videos,
            revision: requestRevision,
            reason: "refresh"
        )
    }

    func appendUnique(_ more: [VideoItem]) {
        let unique = HomeFeedMergePolicy.uniqueAppendVideos(pageCoordinator.filterFeedRecommendations(more), to: videos)
        guard !unique.isEmpty else { return }
        updateFeed(videos + unique, lastSeenMarkerIndex: lastSeenMarkerIndex)
        exposureRecorder.recordIfNeeded(unique, mode: mode)
        snapshotCoordinator.save(
            videos: videos,
            mode: mode,
            lastSeenMarkerIndex: lastSeenMarkerIndex
        )
        mediaPreloadCoordinator.scheduleImagePrefetch(for: Array(unique.prefix(8)))
        mediaPreloadCoordinator.schedulePlaybackPreload(for: unique, initialDelay: 1.2)
        scheduleRecommendMetadataHydration(
            for: unique,
            revision: requestRevision,
            reason: "append"
        )
    }

    func restoreCachedVideosIfAvailable() {
        guard videos.isEmpty else { return }
        guard let snapshot = snapshotCoordinator.load(mode: mode),
              !snapshot.videos.isEmpty
        else { return }
        updateFeed(snapshot.videos, lastSeenMarkerIndex: snapshot.lastSeenMarkerIndex)
        state = .loaded
        Task {
            await ResourceLoadingForegroundPriorityGate.shared.beginFirstScreenPriorityWindow(for: .home)
        }
        mediaPreloadCoordinator.scheduleImagePrefetch(for: Array(videos.prefix(8)))
    }

}
