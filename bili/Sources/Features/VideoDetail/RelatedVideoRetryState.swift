import SwiftUI
import ChunUI

struct RelatedVideoRetryState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: VideoDetailRelatedStyle.retrySpacing) {
            PiliLabel("相关推荐加载失败", systemImage: "rectangle.stack.badge.exclamationmark")
                .piliFont(.base).fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text(message)
                .piliFont(.sm)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Button {
                retry()
            } label: {
                PiliLabel("重新加载", systemImage: "arrow.clockwise")
                    .piliFont(.sm).fontWeight(.semibold)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
    }
}
