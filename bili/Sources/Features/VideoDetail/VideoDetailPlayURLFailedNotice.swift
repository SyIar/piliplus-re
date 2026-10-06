import SwiftUI
import ChunUI

struct VideoDetailPlayURLFailedNotice: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VideoDetailPlayURLRetryButton(
                title: "播放地址加载失败，点击重试",
                systemImage: "arrow.clockwise",
                retry: retry
            )

            Text(message)
                .piliFont(.sm)
                .foregroundStyle(.secondary)
        }
    }
}
