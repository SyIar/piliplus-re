import ChunUI
import SwiftUI

struct UploaderSignatureText: View {
    let sign: String?

    var body: some View {
        if let sign, !sign.isEmpty {
            Text(sign)
                .font(.cc.base)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct UploaderFollowMessage: View {
    let message: String?
    let isFollowing: Bool

    var body: some View {
        if let message, !message.isEmpty {
            PiliLabel(message, systemImage: isFollowing ? "checkmark.circle" : "info.circle")
                .font(.cc.sm)
                .foregroundStyle(isFollowing ? Color.cc.primary : Color.secondary)
        }
    }
}

struct UploaderProfileStatusMessage: View {
    let state: LoadingState

    var body: some View {
        if case .failed(let message) = state {
            PiliLabel(message, systemImage: "exclamationmark.triangle")
                .font(.cc.sm)
                .foregroundStyle(.secondary)
        }
    }
}

struct UploaderStatsRow: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    let owner: VideoOwner
    @ObservedObject var viewModel: UploaderViewModel
    let card: UploaderCard?

    var body: some View {
        HStack(spacing: 14) {
            Button { openRelations(.fans) } label: {
                UploaderStatItem(title: "粉丝", value: viewModel.followerCount ?? card?.fans)
            }.buttonStyle(.plain)
            Button { openRelations(.following) } label: {
                UploaderStatItem(title: "关注", value: viewModel.followingCount ?? card?.attention)
            }.buttonStyle(.plain)
            UploaderStatItem(title: "获赞", value: viewModel.likeCount)
            UploaderStatItem(title: "投稿", value: viewModel.archiveCount ?? loadedVideoCount)
        }
    }

    private var loadedVideoCount: Int? {
        viewModel.videos.isEmpty ? nil : viewModel.videos.count
    }

    private func openRelations(_ kind: PiliRelationList) {
        PiliPresentation.present(.sheet) {
            PiliRelationsView(api: dependencies.api, ownerMID: owner.mid, kind: kind)
                .environmentObject(dependencies)
                .environmentObject(libraryStore)
                .environmentObject(dependencies.api.sessionStore)
        }
    }
}

private struct UploaderStatItem: View {
    let title: String
    let value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(BiliFormatters.compactCount(value))
                .font(.cc.base.weight(.bold))

            Text(title)
                .font(.cc.sm)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
