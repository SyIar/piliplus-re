import SwiftUI

struct InitialVideoDetailControls: View {
    let titleText: String
    let contentWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VideoDetailInfoLoadingPlaceholder(titleText: titleText)
            InitialVideoDetailActionStrip(contentWidth: contentWidth)
        }
        .frame(width: contentWidth, alignment: .leading)
        .allowsHitTesting(false)
    }
}

private struct InitialVideoDetailActionStrip: View {
    let contentWidth: CGFloat

    var body: some View {
        let layout = VideoDetailActionStripLayout(contentWidth: contentWidth)

        VStack(spacing: 12) {
            HStack(spacing: 12) {
                avatarPlaceholder
                SkeletonBlock(width: 100, height: 16, shape: .capsule)
                Spacer(minLength: 12)

                followPlaceholder
                    .frame(width: 84, height: 44)
            }
            HStack(spacing: layout.columnSpacing) {
                ForEach(0..<4, id: \.self) { _ in
                    iconPlaceholder
                        .frame(width: layout.columnWidth, height: layout.rowHeight)
                }
            }
        }
        .frame(
            width: contentWidth,
            alignment: .center
        )
        .accessibilityHidden(true)
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(VideoDetailTheme.secondarySurface.opacity(VideoDetailSkeletonStyle.actionStripFillOpacity))
            .frame(
                width: VideoDetailActionStrip.Metrics.avatarImageSide,
                height: VideoDetailActionStrip.Metrics.avatarImageSide
            )
            .frame(
                width: VideoDetailActionStrip.Metrics.avatarSide,
                height: VideoDetailActionStrip.Metrics.avatarSide
            )
    }

    private var followPlaceholder: some View {
        Capsule(style: .continuous)
            .fill(VideoDetailTheme.secondarySurface.opacity(VideoDetailSkeletonStyle.actionStripFillOpacity))
            .frame(height: VideoDetailActionStrip.Metrics.followHeight)
    }

    private var iconPlaceholder: some View {
        Circle()
            .fill(VideoDetailTheme.secondarySurface.opacity(VideoDetailSkeletonStyle.actionStripFillOpacity))
            .frame(
                width: VideoDetailActionStrip.Metrics.actionLabelSide,
                height: VideoDetailActionStrip.Metrics.actionLabelSide
            )
    }
}
