import ChunUI
import SwiftUI

struct PiliWatchLaterToolsView: View {
    @ObservedObject var viewModel: MineViewModel
    @State private var confirmsClearingAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("管理稍后再看").ccText(font: .cc.lgBold, color: .cc.foreground)
                Spacer()
                Button { AppHelper.shared.dismissSheet() } label: {
                    PikaIcon(PikaIcon.Name.close).frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("关闭")
            }
            CCNeoButton("移除已看完的视频", variant: .secondary, fullWidth: true, disabled: viewModel.isMutatingWatchLater) {
                await clean(.viewed)
            }
            CCNeoButton("移除失效的视频", variant: .secondary, fullWidth: true, disabled: viewModel.isMutatingWatchLater) {
                await clean(.invalid)
            }
            if confirmsClearingAll {
                Text("这会清空账号中所有稍后再看条目。")
                    .ccText(font: .cc.sm, color: .cc.mutedForeground)
                CCNeoButton("确认清空全部", variant: .danger, fullWidth: true, disabled: viewModel.isMutatingWatchLater) {
                    await clean(.all)
                }
            } else {
                CCNeoButton("清空全部", variant: .ghost, fullWidth: true) { confirmsClearingAll = true }
            }
        }
        .padding(24)
        .background(Color.cc.background)
    }

    private func clean(_ mode: WatchLaterCleanup) async {
        do {
            try await viewModel.cleanWatchLater(mode)
            CCToastCenter.shared.show(.success, "稍后再看已更新")
            AppHelper.shared.dismissSheet()
        } catch {
            CCToastCenter.shared.show(.error, error.localizedDescription)
        }
    }
}
