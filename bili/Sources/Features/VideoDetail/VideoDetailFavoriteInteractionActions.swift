import Foundation

extension VideoDetailViewModel {
    /// Return false only when the folder picker should be shown.
    func quickFavoriteIfConfigured() async -> Bool {
        let identity = PiliAccountIdentity(api.requestSnapshot(purpose: .interaction))
        let folderID = libraryStore.quickFavoriteFolder(account: identity.mid)
        guard folderID > 0, let aid = detail.aid else { return false }
        let bvid = detail.bvid
        var needsPicker = false
        _ = await performInteractionMutation(.favorite, isCurrent: {
            identity.matches(api.requestSnapshot(purpose: .interaction)) && isCurrentVideoContext(aid: aid, bvid: bvid)
        }) {
            let folders = try await api.fetchFavoriteFolders(for: aid)
            guard identity.matches(api.requestSnapshot(purpose: .interaction)), isCurrentVideoContext(aid: aid, bvid: bvid), !isPlaybackInvalidatedForNavigation else { throw CancellationError() }
            guard let folder = folders.first(where: { $0.id == folderID }) else {
                libraryStore.setQuickFavoriteFolder(0, account: identity.mid)
                interactionMessage = "默认收藏夹已不可用，请重新选择"
                needsPicker = true; return
            }
            try await api.piliContentWrite("/x/v3/fav/resource/deal", fields: ["rid": String(aid), "type": "2",
                "add_media_ids": folder.isFavorited ? "" : String(folderID), "del_media_ids": folder.isFavorited ? String(folderID) : ""],
                identity: identity, purpose: .interaction)
            guard identity.matches(api.requestSnapshot(purpose: .interaction)), isCurrentVideoContext(aid: aid, bvid: bvid), !isPlaybackInvalidatedForNavigation else { throw CancellationError() }
            interactionState.isFavorited = !folder.isFavorited || folders.contains { $0.id != folderID && $0.isFavorited }
            favoriteFolders = []
            interactionMessage = folder.isFavorited ? "已从\(folder.displayTitle)移除" : "已收藏至\(folder.displayTitle)"
        }
        return !needsPicker
    }

    @discardableResult
    func toggleFavorite() async -> Bool {
        guard let aid = detail.aid else {
            interactionMessage = "没有找到视频 AV 号，无法收藏"
            return false
        }
        let targetState = !interactionState.isFavorited
        return await performInteractionMutation(.favorite) {
            try await api.setVideoFavorite(aid: aid, favorited: targetState)
            interactionState.isFavorited = targetState
        }
    }
}
