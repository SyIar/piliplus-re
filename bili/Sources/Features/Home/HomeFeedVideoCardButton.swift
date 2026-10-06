import SwiftUI

struct HomeFeedVideoCardButton: View {
    let metrics: HomeFeedLayoutMetrics
    let video: VideoItem
    let display: VideoCardDisplayModel
    let actions: HomeFeedContentActions

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Button {
                if let select = actions.onVideoSelect { select(video) }
                else { actions.onVideoTap(video) }
            } label: {
                HomeFeedVideoCardLabel(metrics: metrics, display: display)
                    .environment(\.videoCardHasTrailingMenu, true)
            }
            .buttonStyle(PressPreloadButtonStyle { actions.onVideoPress(video) })
            .contextMenu { PiliRecommendationActions(video: video) }
            .accessibilityIdentifier("video.open.\(video.bvid)")

            // A sibling of the navigation button: tapping the menu must never
            // start playback, prewarm a player or inherit the pressed style.
            Menu { PiliRecommendationActions(video: video) } label: {
                PiliIcon(systemName: "ellipsis", size: 18)
                    .rotationEffect(.degrees(90))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("视频操作")
            .accessibilityIdentifier("video.menu.\(video.bvid)")
        }
    }
}
