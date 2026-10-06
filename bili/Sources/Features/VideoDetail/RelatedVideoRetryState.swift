import SwiftUI
import ChunUI

struct RelatedVideoRetryState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: VideoDetailRelatedStyle.retrySpacing) {
            PiliLabel("相关推荐加载失败", systemImage: "rectangle.stack.badge.exclamationmark")
                .font(.cc.base.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.cc.sm)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Button {
                retry()
            } label: {
                PiliLabel("重新加载", systemImage: "arrow.clockwise")
                    .font(.cc.sm.weight(.semibold))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
    }
}
