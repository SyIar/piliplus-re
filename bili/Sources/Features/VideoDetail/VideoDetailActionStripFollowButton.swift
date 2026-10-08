import SwiftUI

struct VideoDetailActionStripFollowControl: View {
    @Environment(\.appThemeTintColor) private var tint
    let isFollowing: Bool
    let canFollow: Bool
    let isMutating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isFollowing ? "\u{5df2}\u{5173}\u{6ce8}" : "\u{5173}\u{6ce8}")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
                .background(tint.opacity(isFollowing ? 0.06 : 0.12), in: Capsule())
                .frame(minWidth: 64, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isFollowing ? Color.secondary : tint)
        .disabled(!canFollow || isMutating)
        .accessibilityLabel(isFollowing ? "\u{5df2}\u{5173}\u{6ce8}" : "\u{5173}\u{6ce8}")
    }
}
