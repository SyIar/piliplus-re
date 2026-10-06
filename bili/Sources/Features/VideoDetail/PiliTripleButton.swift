import SwiftUI

extension BiliAPIClient {
    func piliTriple(video: VideoItem, identity: PiliAccountIdentity) async throws -> DynamicJSONValue {
        if video.isPGCEpisode, !video.piliIsCourse, let ep = video.pgcEpisodeID {
            return try await piliContentWrite("/pgc/season/episode/like/triple", fields: ["ep_id": String(ep)],
                identity: identity, purpose: .interaction, referer: "https://www.bilibili.com/bangumi/play/ep\(ep)")
        }
        guard let aid = video.aid, aid > 0 else { throw BiliAPIError.missingPayload }
        return try await piliContentWrite("/x/web-interface/archive/like/triple", fields: ["aid": String(aid), "eab_x": "2",
            "ramval": "0", "source": "web_normal", "ga": "1", "spmid": "333.788.0.0", "statistics": "{\"appId\":100,\"platform\":5}"],
            identity: identity, purpose: .interaction, referer: "https://www.bilibili.com/video/\(video.bvid)")
    }
}

extension VideoDetailViewModel {
    func piliTriple(identity: PiliAccountIdentity) async -> Bool {
        let video = detail
        return await performInteractionMutation(.triple, isCurrent: { self.detail.bvid == video.bvid && self.detail.pgcEpisodeID == video.pgcEpisodeID }) {
            let result = try await api.piliTriple(video: video, identity: identity)
            guard identity.matches(api.requestSnapshot(purpose: .interaction)), detail.bvid == video.bvid,
                  detail.pgcEpisodeID == video.pgcEpisodeID else { throw CancellationError() }
            if result["like"].piliInt > 0 { interactionState.isLiked = true }
            if max(result["fav"].piliInt, result["favorite"].piliInt) > 0 { interactionState.isFavorited = true }
            if result["coin"].piliInt > 0 {
                let count = max(result["coin_number"].piliInt, result["multiply"].piliInt)
                interactionState.coinCount = max(interactionState.coinCount, min(2, count > 0 ? count : 1))
            }
        }
    }
}

struct PiliTripleButton: View {
    let viewModel: VideoDetailViewModel
    @ObservedObject var store: VideoDetailInteractionRenderStore
    @State private var confirm = false
    @State private var identity: PiliAccountIdentity?
    @State private var success = 0
    @State private var subject: VideoItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button {
            identity = .init(viewModel.api.requestSnapshot(purpose: .interaction)); subject = viewModel.detail; confirm = true
        } label: {
            HStack(spacing: 5) {
                ForEach(["hand.thumbsup", "bitcoinsign.circle", "star"], id: \.self) { icon in
                    Image(systemName: icon + (success > 0 ? ".fill" : ""))
                        .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : success)
                }
                Text("三连")
            }.font(.system(size: 13, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 8)
        }.buttonStyle(.plain).piliLiquidGlass(in: Capsule(), interactive: true)
            .disabled(store.isMutatingLike || store.isMutatingCoin || store.isMutatingFavorite)
            .confirmationDialog("点赞、投币并收藏？", isPresented: $confirm, titleVisibility: .visible) {
                Button("确认三连") {
                    guard let identity, let subject, subject.bvid == viewModel.detail.bvid, subject.pgcEpisodeID == viewModel.detail.pgcEpisodeID else { return }
                    Task { if await viewModel.piliTriple(identity: identity) { success += 1; Haptics.success() } }
                }
            } message: { Text("平台会按当前互动状态最多使用 2 枚硬币，并加入默认收藏夹。") }
    }
}
