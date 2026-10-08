import SwiftUI

struct VideoDetailActionStrip: View, Equatable {
    enum Metrics {
        static let columnSpacing: CGFloat = 8
        static let rowHeight: CGFloat = 60
        static let actionLabelSide: CGFloat = 44
        static let avatarImageSide: CGFloat = 44
        static let avatarSide: CGFloat = avatarImageSide
        static let followHeight: CGFloat = actionLabelSide
        static let iconSize: CGFloat = 22
        static let avatarPixelSize = 112
    }

    let model: VideoDetailActionStripModel
    let onFollow: () -> Void
    let onLike: () -> Void
    let onCoin: () -> Void
    let onFavorite: () -> Void
    let onShareTap: () -> Void
    var onChooseFavorite: (() -> Void)? = nil

    static func == (lhs: VideoDetailActionStrip, rhs: VideoDetailActionStrip) -> Bool {
        lhs.model == rhs.model
    }

    var body: some View {
        let layout = VideoDetailActionStripLayout(contentWidth: model.contentWidth)

        VideoDetailActionStripButtonRow(
            model: model,
            layout: layout,
            onFollow: onFollow,
            onLike: onLike,
            onCoin: onCoin,
            onFavorite: onFavorite,
            onShareTap: onShareTap,
            onChooseFavorite: onChooseFavorite
        )
        .frame(width: model.contentWidth, alignment: .leading)
    }
}
