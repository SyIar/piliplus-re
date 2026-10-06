import SwiftUI
import ChunUI

struct UploaderFollowButton: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let owner: VideoOwner
    @ObservedObject var viewModel: UploaderViewModel

    var body: some View {
        Group {
            if viewModel.isFollowing {
                Button(action: toggleFollow) {
                    label
                }
                .buttonStyle(.glass)
            } else {
                Button(action: toggleFollow) {
                    label
                }
                .buttonStyle(.glassProminent)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(appTintColor)
        .disabled(viewModel.isMutatingFollow || owner.mid <= 0)
    }

    private var label: some View {
        HStack(spacing: 6) {
            if viewModel.isMutatingFollow {
                ProgressView()
                    .controlSize(.small)
            } else {
                PiliIcon(systemName: viewModel.isFollowing ? "checkmark" : "plus")
                    .font(.cc.sm.weight(.bold))
            }

            Text(viewModel.isFollowing ? "已关注" : "关注")
                .font(.cc.sm.weight(.semibold))
        }
        .frame(minWidth: 62)
    }

    private func toggleFollow() {
        Task {
            let didSucceed = await viewModel.toggleFollow()
            if didSucceed {
                Haptics.success()
            } else {
                Haptics.light()
            }
        }
    }
}
