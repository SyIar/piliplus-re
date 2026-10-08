import SwiftUI

struct VideoDetailActionStripButtonRow: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let model: VideoDetailActionStripModel
    let layout: VideoDetailActionStripLayout
    let onFollow: () -> Void
    let onLike: () -> Void
    let onCoin: () -> Void
    let onFavorite: () -> Void
    let onShareTap: () -> Void
    var onChooseFavorite: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VideoDetailActionStripOwnerAvatar(owner: model.owner)
                if let owner = model.owner {
                    VideoOwnerRouteLink(owner: owner) {
                        Text(owner.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("UP\u{4e3b}")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                VideoDetailActionStripFollowControl(
                    isFollowing: model.isFollowing,
                    canFollow: (model.owner?.mid ?? 0) > 0,
                    isMutating: model.isMutatingFollow,
                    action: onFollow
                )
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("video.actions.follow")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                     count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
                VideoDetailActionStripIconButton(
                    accessibilityTitle: "\u{70b9}\u{8d5e}",
                    systemImage: "hand.thumbsup.fill",
                    foregroundStyle: model.isLiked ? appTintColor : .primary,
                    isDisabled: model.isMutatingLike,
                    action: onLike
                )
                .accessibilityIdentifier("video.actions.like")

                VideoDetailActionStripIconButton(
                    accessibilityTitle: "\u{6295}\u{5e01}",
                    systemImage: "bitcoinsign.circle.fill",
                    foregroundStyle: model.isCoined ? appTintColor : .primary,
                    isDisabled: model.isMutatingCoin || model.coinCount >= 2,
                    action: onCoin
                )
                .accessibilityIdentifier("video.actions.coin")

                VideoDetailActionStripIconButton(
                    accessibilityTitle: model.isFavorited ? "\u{5df2}\u{6536}\u{85cf}" : "\u{6536}\u{85cf}",
                    systemImage: "star.fill",
                    foregroundStyle: model.isFavorited ? appTintColor : .primary,
                    isDisabled: model.isMutatingFavorite || !model.canFavorite,
                    action: onFavorite
                )
                .highPriorityGesture(LongPressGesture().onEnded { _ in
                    guard !model.isMutatingFavorite, model.canFavorite else { return }
                    (onChooseFavorite ?? onFavorite)()
                })
                .accessibilityIdentifier("video.actions.favorite")

                VideoDetailActionStripShareButton(
                    shareURL: model.shareURL,
                    shareSubject: model.shareSubject,
                    shareMessage: model.shareMessage,
                    onShareTap: onShareTap
                )
                .accessibilityIdentifier("video.actions.share")
            }
            .padding(.vertical, 6)
            .piliGlassCard(radius: 16)
        }
    }
}
