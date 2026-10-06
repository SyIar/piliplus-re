import Combine
import Foundation

/// One bounded account-scoped snapshot, shared by feed and related-video filters.
@MainActor
final class PiliBlacklistedCreators: ObservableObject {
    static let shared = PiliBlacklistedCreators()
    @Published private(set) var ids = Set<Int>()
    @Published private(set) var error: String?
    private var identity: PiliAccountIdentity?
    private var refreshed: Date?
    private var task: Task<Set<Int>, Error>?
    private var generation = UUID()
    var effectiveIDs: Set<Int> {
        (UserDefaults.standard.object(forKey: "piliplus.filter.blacklistedCreators") as? Bool ?? true) ? ids : []
    }
    func refresh(api: BiliAPIClient, force: Bool = false) async {
        let context = api.requestSnapshot(), expected = PiliAccountIdentity(api.requestSnapshot())
        if identity != expected {
            task?.cancel(); task = nil; generation = UUID(); ids = []; identity = expected; refreshed = nil; error = nil
        }
        guard context.isLoggedIn else { return }
        if !force, let refreshed, Date().timeIntervalSince(refreshed) < 300 { return }
        if task != nil { return }
        let token = generation
        let request = Task { @MainActor in
            var result = Set<Int>()
            for page in 1...200 {
                try Task.checkCancellation()
                let value = try await api.fetchPiliRelations(kind: .blocked, ownerMID: expected.mid, page: page,
                    group: nil, frequent: false, keyword: "", identity: expected)
                guard expected.matches(api.requestSnapshot()) else { throw CancellationError() }
                result.formUnion(value.users.map(\.id))
                if !value.hasMore { return result }
            }
            throw PiliOfflineError.message("黑名单过大，请在关系管理中检查")
        }
        task = request
        defer { if generation == token { task = nil } }
        do {
            let value = try await request.value
            guard generation == token, expected.matches(api.requestSnapshot()) else { return }
            if value != ids { ids = value }; refreshed = Date(); error = nil
        } catch { if generation == token, !Task.isCancelled { self.error = error.localizedDescription } }
    }
    func didChange(mid: Int, blocked: Bool, account: PiliAccountIdentity) {
        guard identity == account else { return }
        task?.cancel(); task = nil; generation = UUID(); refreshed = nil
        if blocked { ids.insert(mid) } else { ids.remove(mid) }
    }
}
