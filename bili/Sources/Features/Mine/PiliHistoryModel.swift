import Combine
import Foundation

@MainActor
final class PiliHistoryModel: ObservableObject {
    let api: BiliAPIClient
    @Published private(set) var items: [PiliHistoryRecord] = []
    @Published private(set) var tabs = [PiliHistoryTab(id: "all", title: "全部")]
    @Published var selectedType = "all"
    @Published var keyword = ""
    @Published var selection = Set<String>()
    @Published var isSelecting = false
    @Published private(set) var isLoading = false
    @Published private(set) var isMutating = false
    @Published private(set) var isLoadingPause = false
    @Published private(set) var paused: Bool?
    @Published private(set) var hasMore = true
    @Published var errorMessage: String?
    private(set) var credentialVersion: Int
    private var generation = UUID()
    private var pauseGeneration = UUID()
    private var mutationGeneration = UUID()
    private var appliedKeyword = ""
    private var appliedType = "all"
    private var page = 0
    private var cursorMax = 0
    private var cursorViewedAt = 0
    init(api: BiliAPIClient) {
        self.api = api
        credentialVersion = api.requestSnapshot(purpose: .historyRead).playbackCredentialVersion
    }
    private var isAccountCurrent: Bool {
        api.requestSnapshot(purpose: .historyRead).playbackCredentialVersion == credentialVersion
    }
    func activateAccount() async {
        generation = UUID(); isLoading = false; items = []; selection = []; paused = nil
        pauseGeneration = UUID(); mutationGeneration = UUID(); isLoadingPause = false; isMutating = false
        credentialVersion = api.requestSnapshot(purpose: .historyRead).playbackCredentialVersion
        guard api.requestSnapshot(purpose: .historyRead).isLoggedIn else { hasMore = false; return }
        await load(reset: true)
        guard !Task.isCancelled else { return }
        await loadPauseStatus()
    }
    func load(reset: Bool = false) async {
        guard isAccountCurrent else { invalidateAccount(); return }
        guard !isMutating, reset || (!isLoading && hasMore) else { return }
        if reset {
            generation = UUID(); page = 0; cursorMax = 0; cursorViewedAt = 0
            selection = []; items = []; hasMore = true
            appliedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            appliedType = selectedType
        }
        let token = generation, nextPage = page + 1
        isLoading = true; errorMessage = nil
        defer { if token == generation { isLoading = false } }
        do {
            let result = try await api.fetchPiliHistoryPage(type: appliedType, keyword: appliedKeyword, page: nextPage,
                                                          max: cursorMax, viewedAt: cursorViewedAt, credentialVersion: credentialVersion)
            guard !Task.isCancelled, token == generation, isAccountCurrent else { return }
            var seen = Set(items.map(\.id))
            let additions = result.records.filter { seen.insert($0.id).inserted }
            items.append(contentsOf: additions)
            if appliedKeyword.isEmpty && result.tabs.count > 1 { tabs = result.tabs }
            cursorMax = result.cursorMax; cursorViewedAt = result.cursorViewedAt; page = nextPage
            hasMore = result.hasMore && (appliedKeyword.isEmpty || !additions.isEmpty)
        } catch {
            guard !Task.isCancelled, token == generation, isAccountCurrent else { return }
            errorMessage = error.localizedDescription
        }
    }
    func loadPauseStatus() async {
        guard isAccountCurrent, !isLoadingPause, !isMutating else { return }
        let version = credentialVersion
        let token = UUID(); pauseGeneration = token
        isLoadingPause = true
        defer { if pauseGeneration == token { isLoadingPause = false } }
        do {
            let value = try await api.fetchPiliHistoryPaused(credentialVersion: version)
            guard !Task.isCancelled, pauseGeneration == token, isAccountCurrent, version == credentialVersion else { return }
            paused = value
        } catch {
            guard !Task.isCancelled, pauseGeneration == token, isAccountCurrent, version == credentialVersion else { return }
            errorMessage = error.localizedDescription
        }
    }
    func toggle(_ record: PiliHistoryRecord) {
        guard let key = record.deletionKey else { return }
        if selection.contains(key) { selection.remove(key) }
        else if selection.count < 100 { selection.insert(key) }
        else { errorMessage = "每批最多选择 100 条记录" }
    }
    func selectLoaded(finishedOnly: Bool = false) {
        selection = Set(items.filter { !finishedOnly || $0.progress == -1 }.compactMap(\.deletionKey).prefix(100))
        isSelecting = true
    }
    func mutate(_ action: PiliHistoryMutation) async {
        guard isAccountCurrent else { invalidateAccount(); return }
        guard !isMutating, !isLoadingPause else { return }
        generation = UUID(); isLoading = false
        let token = UUID(); mutationGeneration = token
        isMutating = true; errorMessage = nil
        defer { if mutationGeneration == token { isMutating = false } }
        let version = credentialVersion
        do {
            try await api.mutatePiliHistory(action, credentialVersion: version)
            guard mutationGeneration == token, isAccountCurrent, version == credentialVersion else { return }
            switch action {
            case .pause(let value): paused = value
            case .delete(let keys):
                let removed = Set(keys)
                items.removeAll { $0.deletionKey.map(removed.contains) == true }
                selection.subtract(removed)
            case .clear:
                generation = UUID(); items = []; selection = []; hasMore = false
            }
        } catch { if mutationGeneration == token, isAccountCurrent { errorMessage = error.localizedDescription } }
    }
    private func invalidateAccount() {
        generation = UUID(); isLoading = false; items = []; selection = []; paused = nil; hasMore = false
        errorMessage = "账号已切换，请重新加载历史记录"
    }
}
