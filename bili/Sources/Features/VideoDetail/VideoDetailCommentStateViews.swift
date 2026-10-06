import SwiftUI
import ChunUI

struct CommentErrorView: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PiliIcon(systemName: "exclamationmark.circle")
                    .foregroundStyle(Color.cc.warning)
                Text("评论加载失败")
                    .font(.cc.base.weight(.semibold))
            }

            Text(message)
                .font(.cc.sm)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Button(action: retry) {
                PiliLabel("重试", systemImage: "arrow.clockwise")
                    .font(.cc.sm.weight(.semibold))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .tint(appTintColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(VideoDetailTheme.secondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.08), lineWidth: 0.6)
        }
    }
}
