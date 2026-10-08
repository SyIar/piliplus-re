import SwiftUI

struct VideoDetailActionStripIconButton: View {
    let accessibilityTitle: String
    let systemImage: String
    let foregroundStyle: Color
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VideoDetailActionStripIconLabel(
                title: accessibilityTitle,
                systemImage: systemImage,
                foregroundStyle: foregroundStyle
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.52 : 1)
        .accessibilityLabel(accessibilityTitle)
    }
}
