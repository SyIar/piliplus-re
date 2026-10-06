import Foundation

nonisolated enum VideoRecommendationFilterContext: Sendable {
    case feed
    case related
}

nonisolated struct VideoRecommendationFilterConfiguration: Equatable, Sendable {
    let minimumDurationSeconds: Int
    let minimumViewCount: Int
    let minimumLikeRatioPercent: Int
    let blockedKeywords: [String]
    let appliesToRelatedVideos: Bool
    var blockedUserIDs: Set<Int> = []
    var advanced: PiliAdvancedRecommendFilter = .init()

    var isActive: Bool {
        minimumDurationSeconds > 0
            || minimumViewCount > 0
            || minimumLikeRatioPercent > 0
            || !blockedKeywords.isEmpty
            || !blockedUserIDs.isEmpty
            || !advanced.titlePattern.isEmpty || !advanced.zonePattern.isEmpty
    }
}

nonisolated enum VideoRecommendationFilter {
    static func filtered(
        _ videos: [VideoItem],
        configuration: VideoRecommendationFilterConfiguration,
        context: VideoRecommendationFilterContext
    ) -> [VideoItem] {
        guard configuration.isActive else { return videos }
        guard context == .feed || configuration.appliesToRelatedVideos else {
            return videos.filter { !configuration.blockedUserIDs.contains($0.owner?.mid ?? 0) }
        }
        let title = regex(configuration.advanced.titlePattern), zone = regex(configuration.advanced.zonePattern)
        return videos.filter { includes($0, configuration: configuration, context: context, title: title, zone: zone) }
    }

    static func includes(
        _ video: VideoItem,
        configuration: VideoRecommendationFilterConfiguration
    ) -> Bool {
        includes(video, configuration: configuration, context: .feed,
                 title: regex(configuration.advanced.titlePattern), zone: regex(configuration.advanced.zonePattern))
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        guard !pattern.isEmpty else { return nil }
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func includes(_ video: VideoItem, configuration: VideoRecommendationFilterConfiguration,
                                 context: VideoRecommendationFilterContext, title: NSRegularExpression?, zone: NSRegularExpression?) -> Bool {
        if configuration.blockedUserIDs.contains(video.owner?.mid ?? 0) { return false }
        if context == .feed, configuration.advanced.exemptsFollowed, video.piliRecommendation?.followed == true { return true }
        let zoneName = [video.piliZoneName, video.piliRecommendation?.zone].compactMap { $0 }.joined(separator: " ")
        for (pattern, text) in [(title, video.title), (zone, zoneName)] {
            if let pattern, pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { return false }
        }
        if configuration.minimumDurationSeconds > 0,
           let duration = video.duration,
           duration > 0,
           duration < configuration.minimumDurationSeconds {
            return false
        }

        if configuration.minimumViewCount > 0,
           let view = video.stat?.view,
           view >= 0,
           view < configuration.minimumViewCount {
            return false
        }

        if configuration.minimumLikeRatioPercent > 0,
           let like = video.stat?.like,
           let view = video.stat?.view,
           like >= 0,
           view > 0,
           like * 100 < configuration.minimumLikeRatioPercent * view {
            return false
        }

        if !configuration.blockedKeywords.isEmpty {
            let title = normalizedKeywordText(video.title)
            if configuration.blockedKeywords.contains(where: { keyword in
                title.contains(normalizedKeywordText(keyword))
            }) {
                return false
            }
        }

        return true
    }

    private static func normalizedKeywordText(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }
}

@MainActor
extension LibraryStore {
    var videoRecommendationFilterConfiguration: VideoRecommendationFilterConfiguration {
        VideoRecommendationFilterConfiguration(
            minimumDurationSeconds: recommendMinimumDurationSeconds,
            minimumViewCount: recommendMinimumViewCount,
            minimumLikeRatioPercent: recommendMinimumLikeRatioPercent,
            blockedKeywords: blockedRecommendKeywords,
            appliesToRelatedVideos: appliesRecommendFiltersToRelatedVideos,
            blockedUserIDs: PiliBlacklistedCreators.shared.effectiveIDs,
            advanced: advancedRecommendFilter
        )
    }
}
