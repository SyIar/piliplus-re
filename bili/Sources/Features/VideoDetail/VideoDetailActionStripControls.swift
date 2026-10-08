import SwiftUI

struct VideoDetailActionStripShareButton: View {
    let shareURL: URL?
    let shareSubject: String
    let shareMessage: String
    let onShareTap: () -> Void

    var body: some View {
        if let shareURL {
            PiliShareMenu(url: shareURL, title: shareSubject, message: shareMessage) {
                VideoDetailActionStripIconLabel(
                    title: "\u{5206}\u{4eab}",
                    systemImage: "square.and.arrow.up",
                    foregroundStyle: .primary
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { _ in onShareTap() })
            .accessibilityLabel("分享视频")
        } else {
            VideoDetailActionStripIconButton(
                accessibilityTitle: "分享视频",
                systemImage: "square.and.arrow.up",
                foregroundStyle: .secondary,
                isDisabled: true,
                action: {}
            )
        }
    }
}
