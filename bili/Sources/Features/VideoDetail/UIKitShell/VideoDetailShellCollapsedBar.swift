import SwiftUI
import ChunUI

/// UIKit 外壳用：暂停下翻收缩时的折叠工具条。
/// 背景由 `VideoDetailRotationBridgeViewController` 的主题色遮罩提供。
struct VideoDetailShellCollapsedBar: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    @ObservedObject var playerViewModel: PlayerStateViewModel
    let opacity: Double
    let onNavigateBack: () -> Void
    let onRequestFullscreen: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onNavigateBack) {
                PiliIcon(systemName: "chevron.left", size: 16)
                    .font(.cc.baseBold)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            Button {
                playerViewModel.togglePlayback()
            } label: {
                PiliIcon(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill", size: 15)
                    .font(.cc.baseBold)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playerViewModel.isPlaying ? "暂停" : "播放")

            Text(playerViewModel.title)
                .font(.cc.sm.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRequestFullscreen) {
                PiliIcon(systemName: "arrow.up.left.and.arrow.down.right", size: 15)
                    .font(.cc.baseBold)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("全屏")
        }
        .biliLiquidGlassForeground(shadowOpacity: 0.20)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appTintColor)
        .contentShape(Rectangle())
        .opacity(opacity)
    }
}
