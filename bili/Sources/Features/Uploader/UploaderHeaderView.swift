import SwiftUI
import ChunUI

struct UploaderHeaderView: View {
    let owner: VideoOwner
    @ObservedObject var viewModel: UploaderViewModel

    private var card: UploaderCard? {
        viewModel.profile?.card
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploaderIdentityRow(owner: owner, card: card, viewModel: viewModel)
            UploaderSignatureText(sign: card?.sign)
            UploaderFollowMessage(message: viewModel.followMessage, isFollowing: viewModel.isFollowing)
            UploaderProfileStatusMessage(state: viewModel.profileState)
            UploaderStatsRow(owner: owner, viewModel: viewModel, card: card)
            NavigationLink { PiliMemberExtrasView(owner: owner) } label: { PiliLabel("更多空间内容", systemImage: "square.grid.2x2") }.piliFont(.base)
            NavigationLink { PiliMedalWallView(mid: owner.mid) } label: { PiliLabel("粉丝勋章", systemImage: "medal") }.piliFont(.base)
        }
        .padding()
        .biliGlassEffect(
            interactive: false,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.8)
        }
        .padding(.horizontal, 12)
    }
}
