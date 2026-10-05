import Combine
import Foundation

@MainActor
final class PiliFavoriteItemsModel: ObservableObject {
    let api: BiliAPIClient
    let folder: FavoriteFolder
    @Published private(set) var items: [AccountVideoEntry] = []
    @Published private(set) var folders: [FavoriteFolder] = []
    @Published var selected = Set<Int>()
    @Published var keyword = ""
    @Published var order = PiliFavoriteOrder.favoriteTime
    @Published private(set) var isLoading = false
    @Published private(set) var isMutating = false
    @Published private(set) var hasMore = true
    @Published var errorMessage: String?
    let credentialVersion: Int
    private var page = 0
    private var generation = UUID()
    private var appliedKeyword = ""
    private var appliedOrder = PiliFavoriteOrder.favoriteTime
    init(api: BiliAPIClient, folder: FavoriteFolder) {
        self.api = api; self.folder = folder
        credentialVersion = api.requestSnapshot(purpose: .interaction).playbackCredentialVersion
    }
    func load(reset: Bool = false) async {
        guard api.requestSnapshot(purpose: .interaction).playbackCredentialVersion == credentialVersion else {
            generation = UUID(); items = []; folders = []; selected = []; isLoading = false
            errorMessage = "账号已切换，请重新打开收藏夹"; return
        }
        guard reset || (!isLoading && hasMore) else { return }
        if reset {
            generation = UUID(); page = 0; items = []; selected = []; hasMore = true
            appliedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            appliedOrder = order
        }
        let token = generation, version = credentialVersion, next = page + 1
        isLoading = true; errorMessage = nil
        defer { if generation == token { isLoading = false } }
        do {
            let result = try await api.fetchPiliFavoriteItems(folderID: folder.id, page: next, keyword: appliedKeyword, order: appliedOrder)
            guard !Task.isCancelled, generation == token,
                  api.requestSnapshot(purpose: .interaction).playbackCredentialVersion == version else { return }
            var seen = Set(items.map(\.bvid))
            items.append(contentsOf: result.entries.filter { seen.insert($0.bvid).inserted })
            page = next; hasMore = result.hasMore
        } catch {
            guard !Task.isCancelled, generation == token else { return }
            errorMessage = error.localizedDescription
        }
    }
    func loadTargets() async {
        do {
            let values = try await api.fetchFavoriteFolders()
            guard api.requestSnapshot(purpose: .interaction).playbackCredentialVersion == credentialVersion else { return }
            folders = values.filter { $0.id != folder.id }
        } catch { errorMessage = error.localizedDescription }
    }
    func toggle(_ aid: Int) {
        if selected.contains(aid) { selected.remove(aid) }
        else if selected.count < 100 { selected.insert(aid) }
        else { errorMessage = "每批最多选择 100 个视频" }
    }
    func selectLoaded() { selected = Set(items.compactMap(\.aid).filter { $0 > 0 }.prefix(100)) }
    func downloadRequest(all: Bool) throws -> PiliBatchDownloadRequest {
        guard api.requestSnapshot(purpose: .interaction).playbackCredentialVersion == credentialVersion else {
            throw PiliOfflineError.message("账号已切换，请重新打开收藏夹")
        }
        let source: PiliBatchDownloadSource = all
            ? .favorite(id: folder.id, keyword: appliedKeyword, order: appliedOrder)
            : .selected(items.filter { $0.aid.map(selected.contains) ?? false }.map(\.videoItem))
        return PiliBatchDownloadRequest(source: source, title: folder.displayTitle,
                                        purpose: .interaction, credentialVersion: credentialVersion)
    }
    func mutate(_ action: PiliFavoriteResourceAction) async -> Bool {
        guard !isMutating, !selected.isEmpty else { return false }
        isMutating = true; errorMessage = nil
        defer { isMutating = false }
        do {
            try await api.mutatePiliFavoriteItems(folderID: folder.id, aids: Array(selected), action: action, credentialVersion: credentialVersion)
            guard api.requestSnapshot(purpose: .interaction).playbackCredentialVersion == credentialVersion else { return false }
            selected = []; await load(reset: true)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func clean() async -> Bool {
        guard !isMutating else { return false }
        isMutating = true; errorMessage = nil
        defer { isMutating = false }
        do {
            try await api.cleanPiliFavoriteFolder(id: folder.id, credentialVersion: credentialVersion)
            guard api.requestSnapshot(purpose: .interaction).playbackCredentialVersion == credentialVersion else { return false }
            await load(reset: true); return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
}
