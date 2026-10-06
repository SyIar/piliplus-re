import SwiftUI

struct PiliSeasonActionsView: View {
    let api: BiliAPIClient
    let seasonID: Int
    var isCourse = false
    var collectionBVID: String?
    @State private var identity: PiliAccountIdentity?
    @State private var following = false
    @State private var status = 2
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(following ? "取消\(actionTitle)" : actionTitle, systemImage: following ? "checkmark.circle.fill" : "plus.circle") { change(follow: !following) }
                if following && !isCourse && collectionBVID == nil {
                    Menu(status == 1 ? "想看" : status == 3 ? "看过" : "在看") {
                        Button("想看") { change(status: 1) }; Button("在看") { change(status: 2) }; Button("看过") { change(status: 3) }
                    }
                }
            }.buttonStyle(.bordered).disabled(!loaded || busy)
            if let error { Text(error).font(.caption).foregroundStyle(.red); if !loaded { Button("重新加载状态") { Task { await load() } } } }
        }.task(id: "\(seasonID):\(isCourse):\(collectionBVID ?? "")") { identity = .init(api.requestSnapshot(purpose: .main)); await load() }
    }
    private var actionTitle: String { collectionBVID != nil ? "订阅合集" : isCourse ? "收藏课程" : "追番" }
    private func load() async {
        guard let identity, identity.mid > 0, seasonID > 0 else { error = "登录后可\(actionTitle)"; return }
        do {
            if let bvid = collectionBVID {
                let value = try await api.piliContentRead("/x/web-interface/archive/relation", query: ["bvid": bvid], identity: identity)
                following = value["season_fav"].piliInt == 1
            } else if isCourse {
                let value = try await api.piliContentRead("/pugv/view/web/season", query: ["season_id": String(seasonID)], identity: identity)
                following = value["user_status"]["favored"].piliInt == 1
            } else {
                let value = try await api.piliContentRead("/pgc/view/web/season/user/status", query: ["season_id": String(seasonID)], identity: identity)
                following = value["follow"].piliInt == 1; status = max(1, min(3, value["follow_status"].piliInt))
            }
            loaded = true; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func change(follow: Bool? = nil, status: Int? = nil) {
        guard let identity, loaded, !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do {
                if let follow {
                    if collectionBVID != nil { try await api.piliSubscribeCollection(seasonID: seasonID, add: follow, identity: identity) }
                    else if isCourse { try await api.piliCourseFavorite(seasonID: seasonID, add: follow, identity: identity) }
                    else { try await api.piliFollowSeason(seasonID: seasonID, follow: follow, identity: identity) }
                    following = follow
                } else if let status { try await api.piliSeasonStatus(seasonID: seasonID, status: status, identity: identity); self.status = status }
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
}
