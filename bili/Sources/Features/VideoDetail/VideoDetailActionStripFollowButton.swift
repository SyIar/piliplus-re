import SwiftUI
import ChunUI

struct VideoDetailActionStripFollowControl: View {
    let isFollowing: Bool
    let canFollow: Bool
    let isMutating: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isFollowing {
                Button(action: action) {
                    VideoDetailActionStripFollowLabel(isFollowing: isFollowing)
                }
                .buttonBorderShape(.capsule)
                .disabled(!canFollow || isMutating)
                .opacity((canFollow && !isMutating) ? 1 : 0.58)
                .accessibilityLabel(isFollowing ? "已关注" : "关注")
                .biliGlassButtonStyle()
            } else {
                Button(action: action) {
                    VideoDetailActionStripFollowLabel(isFollowing: isFollowing)
                }
                .buttonBorderShape(.capsule)
                .disabled(!canFollow || isMutating)
                .opacity((canFollow && !isMutating) ? 1 : 0.58)
                .accessibilityLabel(isFollowing ? "已关注" : "关注")
                .biliGlassButtonStyle(prominent: true)
            }
        }
    }
}

private struct VideoDetailActionStripFollowLabel: View {
    let isFollowing: Bool

    var body: some View {
        Text(isFollowing ? "已关注" : "关注")
            .piliFont(.sm).fontWeight(.semibold)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minWidth: 60, minHeight: 44)
    }
}
