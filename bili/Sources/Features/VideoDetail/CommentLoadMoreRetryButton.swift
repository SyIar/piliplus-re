import SwiftUI
import ChunUI

struct CommentLoadMoreRetryButton: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        Button(action: retry) {
            PiliLabel("评论加载失败，点按重试", systemImage: "arrow.clockwise")
                .piliFont(.sm).fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityHint(message)
    }
}
