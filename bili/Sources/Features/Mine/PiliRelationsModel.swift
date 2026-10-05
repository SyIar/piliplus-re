import Combine
import Foundation

@MainActor
final class PiliRelationsModel: ObservableObject {
    let api: BiliAPIClient
    let identity: PiliAccountIdentity
    let ownerMID: Int
    @Published var kind: PiliRelationList
    @Published var groupID: Int?
    @Published var frequent = false
    @Published var keyword = ""
    @Published private(set) var users: [PiliRelationUser] = []
    @Published private(set) var groups: [PiliFollowGroup] = []
    @Published private(set) var total: Int?
    @Published private(set) var hasMore = false
    @Published private(set) var loading = false
    @Published private(set) var mutating = false
    @Published var errorMessage: String?
    private var generation = UUID()
    private var page = 0
    private var applied: Filter
    private struct Filter {
        let kind: PiliRelationList
        let group: Int?
        let frequent: Bool
        let keyword: String
    }
    init(api: BiliAPIClient, ownerMID: Int? = nil, kind: PiliRelationList = .following) {
        self.api = api; identity = PiliAccountIdentity(api.requestSnapshot(purpose: .main))
        self.ownerMID = ownerMID ?? identity.mid; self.kind = kind
        applied = Filter(kind: kind, group: nil, frequent: false, keyword: "")
    }
    var isOwn: Bool { ownerMID > 0 && ownerMID == identity.mid }
    var isCurrent: Bool {
        let current = api.requestSnapshot(purpose: .main)
        return identity.mid == (current.currentUserMID ?? 0) && identity.version == current.playbackCredentialVersion
    }
    var isShowingSpecial: Bool { applied.kind == .following && applied.group == -10 && applied.keyword.isEmpty }
    func start() async {
        guard !mutating else { return }
        await load(reset: true)
        if isOwn, !Task.isCancelled { await refreshGroups() }
    }
    func refreshGroups(allowDuringMutation: Bool = false) async {
        guard isCurrent, isOwn, !mutating || allowDuringMutation else { return }
        do {
            let values = try await api.fetchPiliFollowGroups(identity: identity)
            guard !Task.isCancelled, isCurrent else { return }
            groups = values
        } catch { if !Task.isCancelled, isCurrent { errorMessage = error.localizedDescription } }
    }
    func load(reset: Bool = false, preserveFilter: Bool = false, allowDuringMutation: Bool = false) async {
        guard isCurrent else { invalidate(); return }
        guard !mutating || allowDuringMutation, reset || (!loading && hasMore) else { return }
        if reset {
            generation = UUID(); page = 0; users = []; total = nil; hasMore = true
            if !preserveFilter {
                let key = kind == .following ? keyword.trimmingCharacters(in: .whitespacesAndNewlines) : ""
                applied = Filter(kind: kind, group: key.isEmpty && kind == .following ? groupID : nil, frequent: frequent, keyword: key)
            }
        }
        let token = generation, nextPage = page + 1, filter = applied
        loading = true; errorMessage = nil
        defer { if token == generation { loading = false } }
        do {
            let result = try await api.fetchPiliRelations(kind: filter.kind, ownerMID: ownerMID, page: nextPage,
                group: filter.group, frequent: filter.frequent, keyword: filter.keyword, identity: identity)
            guard !Task.isCancelled, token == generation, isCurrent else { return }
            var seen = Set(users.map(\.id))
            let additions = result.users.filter { seen.insert($0.id).inserted }
            users.append(contentsOf: additions); total = result.total; page = nextPage
            hasMore = result.hasMore && !additions.isEmpty
        } catch { if !Task.isCancelled, token == generation, isCurrent { errorMessage = error.localizedDescription } }
    }
    @discardableResult
    func perform(_ action: PiliRelationMutation) async -> Bool {
        guard isCurrent, isOwn else { invalidate(); return false }
        guard !mutating else { return false }
        generation = UUID(); loading = false; mutating = true; errorMessage = nil
        defer { mutating = false }
        do {
            try await api.mutatePiliRelation(action, identity: identity)
            guard isCurrent else { invalidate(); return false }
            // A deleted group can no longer be used as the pagination source.
            if case .deleteGroup(let id) = action, applied.group == id {
                groupID = nil
                applied = Filter(kind: applied.kind, group: nil, frequent: applied.frequent, keyword: applied.keyword)
            }
            await load(reset: true, preserveFilter: true, allowDuringMutation: true)
            await refreshGroups(allowDuringMutation: true)
            return true
        } catch { if isCurrent { errorMessage = error.localizedDescription }; return false }
    }
    func invalidate() {
        generation = UUID(); loading = false; hasMore = false; users = []; groups = []; total = nil
        errorMessage = "账号已切换，请重新打开关注管理"
    }
}
