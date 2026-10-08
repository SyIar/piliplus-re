import Foundation
import Combine

@MainActor
final class MineViewModel: ObservableObject {
    @Published var statistics: MineStatistics?
    private var statisticsCredentialVersion: Int?
    private var favoritesGeneration = UUID()
    private var favoritesCredentialVersion: Int?
    @Published var state: LoadingState = .idle
    @Published var loginMessage = ""
    @Published var qrLoginState: QRCodeLoginState = .idle
    @Published var historyState: LoadingState = .idle
    @Published var favoriteState: LoadingState = .idle
    @Published var watchLaterState: LoadingState = .idle
    @Published var watchLaterFilter = PiliWatchLaterFilter()
    @Published private(set) var watchLaterHasMore = false
    @Published private(set) var watchLaterLoadMoreState: LoadingState = .idle
    private var watchLaterPage = 1
    @Published private(set) var watchLaterGeneration = UUID()
    private var appliedWatchLaterFilter = PiliWatchLaterFilter()
    private var watchLaterRequestCredentialVersion: Int?
    @Published private(set) var isMutatingWatchLater = false
    @Published private(set) var historyLoadMoreState: LoadingState = .idle {
        didSet { accountLibraryRevision &+= 1 }
    }
    @Published private(set) var historyHasMore = false {
        didSet { accountLibraryRevision &+= 1 }
    }
    @Published var accountHistory: [AccountVideoEntry] = [] {
        didSet { accountLibraryRevision &+= 1 }
    }
    @Published var accountFavorites: [AccountVideoEntry] = [] {
        didSet { accountLibraryRevision &+= 1 }
    }
    @Published var accountWatchLater: [AccountVideoEntry] = [] {
        didSet { accountLibraryRevision &+= 1 }
    }
    @Published var favoriteFolders: [FavoriteFolder] = [] {
        didSet { accountLibraryRevision &+= 1 }
    }
    @Published var favoriteFolderEntries: [Int: [AccountVideoEntry]] = [:] {
        didSet { favoriteFolderRevision &+= 1 }
    }
    @Published var favoriteFolderEntryStates: [Int: LoadingState] = [:] {
        didSet { favoriteFolderRevision &+= 1 }
    }
    @Published private(set) var favoriteFolderLoadMoreStates: [Int: LoadingState] = [:] {
        didSet { favoriteFolderRevision &+= 1 }
    }
    @Published private(set) var favoriteFolderHasMore: [Int: Bool] = [:] {
        didSet { favoriteFolderRevision &+= 1 }
    }
    @Published private(set) var accountLibraryRevision = 0
    @Published private(set) var favoriteFolderRevision = 0

    private let api: BiliAPIClient
    var offlineDownloadAPI: BiliAPIClient { api }

    func watchLaterDownloadRequest(selected: Set<Int>?) throws -> PiliBatchDownloadRequest {
        guard let version = watchLaterRequestCredentialVersion,
              api.requestSnapshot(purpose: .historyRead).playbackCredentialVersion == version else {
            throw PiliOfflineError.message("\u{8d26}\u{53f7}\u{5df2}\u{5207}\u{6362}，\u{8bf7}\u{91cd}\u{65b0}\u{52a0}\u{8f7d}\u{7a0d}\u{540e}\u{518d}\u{770b}")
        }
        let source: PiliBatchDownloadSource
        if let selected {
            source = .selected(accountWatchLater.filter { $0.aid.map(selected.contains) ?? false }.map(\.videoItem))
        } else { source = .watchLater(appliedWatchLaterFilter) }
        return PiliBatchDownloadRequest(source: source, title: "\u{7a0d}\u{540e}\u{518d}\u{770b}", purpose: .historyRead, credentialVersion: version)
    }
    private let sessionStore: SessionStore
    private var qrLoginTask: Task<Void, Never>?
    private let accountLibraryPageSize = 20
    private var historyCursor: AccountHistoryCursor?
    private var favoriteFolderPages: [Int: Int] = [:]
    private var watchLaterCredentialVersion: Int?
    private var favoriteFolderCredentialVersions: [Int: Int] = [:]

    init(api: BiliAPIClient, sessionStore: SessionStore) {
        self.api = api
        self.sessionStore = sessionStore
    }

    func refreshUser() async {
        guard sessionStore.isLoggedIn else { return }
        do {
            let user = try await api.fetchNavUser()
            if user.isLogin == true {
                sessionStore.updateUser(user)
                await refreshAccountLibrary()
            } else {
                try? sessionStore.logout()
                loginMessage = "\u{767b}\u{5f55}\u{5df2}\u{5931}\u{6548}，\u{8bf7}\u{91cd}\u{65b0}\u{767b}\u{5f55}"
            }
        } catch {
            sessionStore.updateUser(nil)
        }
    }

    func refreshAccountLibrary() async {
        guard sessionStore.isLoggedIn else {
            resetAccountLibraryState()
            return
        }

        async let stats: Void = refreshStatistics()
        async let history: Void = refreshHistory()
        async let favorites: Void = refreshFavorites()
        async let watchLater: Void = refreshWatchLater()
        _ = await (history, favorites, watchLater, stats)
    }

    func refreshHistory() async {
        guard sessionStore.isLoggedIn else { return }
        historyState = .loading
        historyLoadMoreState = .idle
        historyCursor = nil
        historyHasMore = false
        do {
            let page = try await api.fetchAccountHistoryPage(pageSize: accountLibraryPageSize)
            accountHistory = Self.uniqued(page.entries)
            historyCursor = page.nextHistoryCursor
            historyHasMore = page.hasMore
            historyState = .loaded
        } catch {
            historyState = .failed(error.localizedDescription)
        }
    }

    func refreshStatistics() async {
        let version = sessionStore.playbackCredentialVersion
        if statisticsCredentialVersion != version { statistics = nil }
        statisticsCredentialVersion = version
        guard sessionStore.isLoggedIn else { return }
        let result = try? await api.fetchMineStatistics()
        guard !Task.isCancelled, version == sessionStore.playbackCredentialVersion else { return }
        if let result { statistics = result }
    }

    func refreshFavorites() async {
        guard sessionStore.isLoggedIn else { return }
        let version = sessionStore.interactionAccountCredentialVersion
        if favoritesCredentialVersion != version { favoriteFolders = []; accountFavorites = [] }
        favoritesCredentialVersion = version
        favoritesGeneration = UUID(); let generation = favoritesGeneration
        favoriteState = .loading
        do {
            let folders = try await api.fetchFavoriteFolders()
            guard !Task.isCancelled, version == sessionStore.interactionAccountCredentialVersion,
                  favoritesGeneration == generation else { return }
            favoriteFolders = folders
            let entries = try await api.fetchAccountFavorites()
            guard !Task.isCancelled, version == sessionStore.interactionAccountCredentialVersion,
                  favoritesGeneration == generation else { return }
            accountFavorites = entries
            favoriteState = .loaded
        } catch {
            guard !Task.isCancelled, version == sessionStore.interactionAccountCredentialVersion,
                  favoritesGeneration == generation else { return }
            favoriteState = .failed(error.localizedDescription)
        }
    }

    func refreshWatchLater(applyingFilter: Bool = true) async {
        guard sessionStore.isLoggedIn else { return }
        watchLaterGeneration = UUID(); let token = watchLaterGeneration
        let credentialVersion = sessionStore.historyAccountCredentialVersion
        let requestVersion = api.requestSnapshot(purpose: .historyRead).playbackCredentialVersion
        if applyingFilter {
            appliedWatchLaterFilter = watchLaterFilter
            appliedWatchLaterFilter.keyword = appliedWatchLaterFilter.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        watchLaterState = .loading; watchLaterLoadMoreState = .idle
        watchLaterPage = 1; watchLaterHasMore = false; accountWatchLater = []
        do {
            let result = try await api.fetchPiliWatchLaterPage(page: 1, filter: appliedWatchLaterFilter)
            guard !Task.isCancelled, watchLaterGeneration == token,
                  sessionStore.historyAccountCredentialVersion == credentialVersion else { return }
            accountWatchLater = Self.uniqued(result.entries)
            watchLaterCredentialVersion = credentialVersion
            watchLaterRequestCredentialVersion = requestVersion
            watchLaterHasMore = result.hasMore; watchLaterState = .loaded
        } catch {
            guard !Task.isCancelled, watchLaterGeneration == token,
                  sessionStore.historyAccountCredentialVersion == credentialVersion else { return }
            watchLaterState = .failed(error.localizedDescription)
        }
    }

    func loadMoreWatchLater() async {
        guard watchLaterHasMore, !watchLaterState.isLoading, !watchLaterLoadMoreState.isLoading else { return }
        let token = watchLaterGeneration, page = watchLaterPage + 1
        let credentialVersion = sessionStore.historyAccountCredentialVersion
        guard watchLaterCredentialVersion == credentialVersion else { return }
        watchLaterLoadMoreState = .loading
        do {
            let result = try await api.fetchPiliWatchLaterPage(page: page, filter: appliedWatchLaterFilter)
            guard !Task.isCancelled, watchLaterGeneration == token,
                  sessionStore.historyAccountCredentialVersion == credentialVersion else { return }
            accountWatchLater = Self.appendingUnique(result.entries, to: accountWatchLater)
            watchLaterPage = page; watchLaterHasMore = result.hasMore; watchLaterLoadMoreState = .loaded
        } catch {
            guard !Task.isCancelled, watchLaterGeneration == token,
                  sessionStore.historyAccountCredentialVersion == credentialVersion else { return }
            watchLaterLoadMoreState = .failed(error.localizedDescription)
        }
    }

    func watchLaterDestinationFolders() async throws -> [FavoriteFolder] {
        let token = watchLaterGeneration
        let result = try await api.fetchPiliFavoriteDestinations(purpose: .historyRead)
        guard token == watchLaterGeneration, watchLaterCredentialVersion == sessionStore.historyAccountCredentialVersion else { throw CancellationError() }
        return result
    }

    func batchWatchLater(aids: [Int], targetFolder: Int? = nil, move: Bool = false) async throws {
        guard !isMutatingWatchLater, !watchLaterState.isLoading,
              watchLaterCredentialVersion == sessionStore.historyAccountCredentialVersion,
              let requestVersion = watchLaterRequestCredentialVersion else {
            throw PiliOfflineError.message("\u{5217}\u{8868}\u{6b63}\u{5728}\u{66f4}\u{65b0}\u{6216}\u{8d26}\u{53f7}\u{5df2}\u{5207}\u{6362}，\u{8bf7}\u{91cd}\u{65b0}\u{52a0}\u{8f7d}")
        }
        isMutatingWatchLater = true
        defer { isMutatingWatchLater = false }
        try await api.mutatePiliWatchLater(aids: aids, targetFolder: targetFolder, move: move, credentialVersion: requestVersion)
        guard api.requestSnapshot(purpose: .historyRead).playbackCredentialVersion == requestVersion else { throw CancellationError() }
        await refreshWatchLater(applyingFilter: false)
    }

    func removeWatchLater(_ entry: AccountVideoEntry) async throws {
        guard let aid = entry.aid, aid > 0 else { throw BiliAPIError.missingPayload }
        try await batchWatchLater(aids: [aid])
    }

    func playbackQueue(for folder: FavoriteFolder) -> PiliPlaybackQueue? {
        guard favoriteFolderCredentialVersions[folder.id] == sessionStore.interactionAccountCredentialVersion else { return nil }
        return PiliPlaybackQueue(
            source: .favoriteFolder(folder.id),
            credentialVersion: sessionStore.interactionAccountCredentialVersion,
            bvids: (favoriteFolderEntries[folder.id] ?? []).map(\.bvid),
            nextPage: favoriteFolderHasMore[folder.id] == true ? (favoriteFolderPages[folder.id] ?? 1) + 1 : nil,
            titles: Dictionary((favoriteFolderEntries[folder.id] ?? []).map { ($0.bvid, $0.videoItem.title) }, uniquingKeysWith: { first, _ in first })
        )
    }

    var watchLaterPlaybackQueue: PiliPlaybackQueue? {
        guard watchLaterCredentialVersion == sessionStore.historyAccountCredentialVersion else { return nil }
        return PiliPlaybackQueue(
            source: .watchLaterFiltered(appliedWatchLaterFilter),
            credentialVersion: sessionStore.historyAccountCredentialVersion,
            bvids: accountWatchLater.map(\.bvid),
            nextPage: watchLaterHasMore ? watchLaterPage + 1 : nil,
            titles: Dictionary(accountWatchLater.map { ($0.bvid, $0.videoItem.title) }, uniquingKeysWith: { first, _ in first })
        )
    }

    func cleanWatchLater(_ mode: WatchLaterCleanup) async throws {
        guard !isMutatingWatchLater, !watchLaterState.isLoading,
              watchLaterCredentialVersion == sessionStore.historyAccountCredentialVersion,
              watchLaterRequestCredentialVersion == api.requestSnapshot(purpose: .historyRead).playbackCredentialVersion else {
            throw PiliOfflineError.message("\u{5217}\u{8868}\u{6b63}\u{5728}\u{66f4}\u{65b0}\u{6216}\u{8d26}\u{53f7}\u{5df2}\u{5207}\u{6362}，\u{8bf7}\u{91cd}\u{65b0}\u{52a0}\u{8f7d}")
        }
        isMutatingWatchLater = true
        defer { isMutatingWatchLater = false }
        let version = watchLaterRequestCredentialVersion
        try await api.cleanWatchLater(mode, credentialVersion: version)
        guard api.requestSnapshot(purpose: .historyRead).playbackCredentialVersion == version else { throw CancellationError() }
        await refreshWatchLater(applyingFilter: false)
    }

    func refreshFavoriteFolder(_ folder: FavoriteFolder) async {
        guard sessionStore.isLoggedIn else { return }
        let credentialVersion = sessionStore.interactionAccountCredentialVersion
        favoriteFolderEntryStates[folder.id] = .loading
        favoriteFolderLoadMoreStates[folder.id] = .idle
        favoriteFolderPages[folder.id] = 1
        favoriteFolderHasMore[folder.id] = false
        do {
            let page = try await api.fetchFavoriteFolderVideoPage(
                folderID: folder.id,
                page: 1,
                pageSize: accountLibraryPageSize
            )
            guard !Task.isCancelled, sessionStore.interactionAccountCredentialVersion == credentialVersion else { return }
            favoriteFolderEntries[folder.id] = Self.uniqued(page.entries)
            favoriteFolderCredentialVersions[folder.id] = credentialVersion
            favoriteFolderHasMore[folder.id] = page.hasMore
            favoriteFolderEntryStates[folder.id] = .loaded
        } catch {
            guard !Task.isCancelled, sessionStore.interactionAccountCredentialVersion == credentialVersion else { return }
            favoriteFolderEntryStates[folder.id] = .failed(error.localizedDescription)
        }
    }

    func loadMoreHistoryIfNeeded(current item: AccountVideoEntry?) async {
        guard let item, accountHistory.last?.id == item.id else { return }
        await loadMoreHistory()
    }

    func loadMoreHistory() async {
        guard sessionStore.isLoggedIn,
              historyHasMore,
              !historyState.isLoading,
              !historyLoadMoreState.isLoading
        else { return }
        historyLoadMoreState = .loading
        do {
            let page = try await api.fetchAccountHistoryPage(
                cursor: historyCursor,
                pageSize: accountLibraryPageSize
            )
            let previousCount = accountHistory.count
            accountHistory = Self.appendingUnique(page.entries, to: accountHistory)
            historyCursor = page.nextHistoryCursor
            historyHasMore = page.hasMore && accountHistory.count > previousCount
            historyLoadMoreState = .idle
        } catch {
            historyLoadMoreState = .failed(error.localizedDescription)
        }
    }

    func loadMoreFavoriteFolderIfNeeded(_ folder: FavoriteFolder, current item: AccountVideoEntry?) async {
        guard let item, favoriteFolderEntries[folder.id]?.last?.id == item.id else { return }
        await loadMoreFavoriteFolder(folder)
    }

    func loadMoreFavoriteFolder(_ folder: FavoriteFolder) async {
        guard sessionStore.isLoggedIn,
              favoriteFolderCredentialVersions[folder.id] == sessionStore.interactionAccountCredentialVersion,
              favoriteFolderHasMore[folder.id] == true,
              !(favoriteFolderEntryStates[folder.id]?.isLoading ?? false),
              !(favoriteFolderLoadMoreStates[folder.id]?.isLoading ?? false)
        else { return }
        let credentialVersion = sessionStore.interactionAccountCredentialVersion
        let nextPage = (favoriteFolderPages[folder.id] ?? 1) + 1
        favoriteFolderLoadMoreStates[folder.id] = .loading
        do {
            let page = try await api.fetchFavoriteFolderVideoPage(
                folderID: folder.id,
                page: nextPage,
                pageSize: accountLibraryPageSize
            )
            guard !Task.isCancelled, sessionStore.interactionAccountCredentialVersion == credentialVersion else { return }
            let previousCount = favoriteFolderEntries[folder.id]?.count ?? 0
            favoriteFolderEntries[folder.id] = Self.appendingUnique(
                page.entries,
                to: favoriteFolderEntries[folder.id] ?? []
            )
            favoriteFolderPages[folder.id] = nextPage
            favoriteFolderHasMore[folder.id] = page.hasMore
                && (favoriteFolderEntries[folder.id]?.count ?? 0) > previousCount
            favoriteFolderLoadMoreStates[folder.id] = .idle
        } catch {
            guard !Task.isCancelled, sessionStore.interactionAccountCredentialVersion == credentialVersion else { return }
            favoriteFolderLoadMoreStates[folder.id] = .failed(error.localizedDescription)
        }
    }

    func completeWebLogin(with cookies: [HTTPCookie]) async {
        do {
            cancelQRCodeLogin()
            try sessionStore.saveLoginCookies(cookies, credentialKind: .web)
            loginMessage = "\u{7f51}\u{9875}\u{767b}\u{5f55}\u{6210}\u{529f}，\u{9996}\u{9875}\u{63a8}\u{8350}\u{5efa}\u{8bae}\u{4f18}\u{5148}\u{9009}\u{62e9}\u{7f51}\u{9875}\u{7aef}。"
            await refreshUser()
        } catch {
            loginMessage = error.localizedDescription
        }
    }

    func logout() {
        cancelQRCodeLogin()
        try? sessionStore.logout()
        BiliWebCookieStore.clearLoginCookies()
        resetAccountLibraryState()
        loginMessage = ""
        qrLoginState = .idle
    }

    func startQRCodeLogin() async {
        cancelQRCodeLogin()
        qrLoginState = .loading
        loginMessage = ""

        do {
            let info = try await api.generateAppQRCodeLogin()
            guard !Task.isCancelled else { return }
            let autoConfirmMessage: String
            do {
                try await api.confirmAppQRCodeLoginWithCurrentSession(authCode: info.qrcodeKey)
                autoConfirmMessage = ""
            } catch {
                autoConfirmMessage = error.localizedDescription
            }
            guard !Task.isCancelled else { return }
            if autoConfirmMessage.isEmpty {
                qrLoginState = .scanned(info, "\u{5df2}\u{7528}\u{5f53}\u{524d}\u{8d26}\u{53f7}\u{786e}\u{8ba4}，\u{6b63}\u{5728}\u{83b7}\u{53d6}\u{79fb}\u{52a8}\u{7aef}\u{51ed}\u{8bc1}")
            } else {
                qrLoginState = .waiting(info, "\u{81ea}\u{52a8}\u{786e}\u{8ba4}\u{672a}\u{5b8c}\u{6210}：\(autoConfirmMessage)。\u{53ef}\u{7528} B \u{7ad9}\u{626b}\u{7801}\u{6216}\u{6253}\u{5f00}\u{786e}\u{8ba4}")
            }
            qrLoginTask = Task { [weak self] in
                await self?.pollQRCodeLogin(info)
            }
        } catch {
            qrLoginState = .failed(error.localizedDescription)
        }
    }

    func cancelQRCodeLogin() {
        qrLoginTask?.cancel()
        qrLoginTask = nil
    }

    func sendAppSMSCode(phone: String, countryCode: String) async throws -> String {
        cancelQRCodeLogin()
        let info = try await api.sendAppSMSCode(
            phone: Self.normalizedPhone(phone),
            countryCode: Self.normalizedCountryCode(countryCode)
        )
        guard let captchaKey = info.captchaKey, !captchaKey.isEmpty else {
            throw BiliAPIError.missingPayload
        }
        return captchaKey
    }

    func completeAppSMSLogin(
        phone: String,
        countryCode: String,
        code: String,
        captchaKey: String
    ) async throws {
        cancelQRCodeLogin()
        let loginData = try await api.loginWithAppSMS(
            phone: Self.normalizedPhone(phone),
            countryCode: Self.normalizedCountryCode(countryCode),
            code: code.trimmingCharacters(in: .whitespacesAndNewlines),
            captchaKey: captchaKey
        )
        let cookieValues = loginData.loginCookieValues
        guard !cookieValues.isEmpty else {
            throw BiliAPIError.missingPayload
        }
        try sessionStore.saveLoginCookies(cookieValues, credentialKind: .appSMS)
        guard sessionStore.isLoggedIn else {
            throw BiliAPIError.missingSESSDATA
        }
        if sessionStore.appAccessKey() == nil {
            loginMessage = "\u{767b}\u{5f55}\u{6210}\u{529f}，\u{4f46}\u{6ca1}\u{6709}\u{62ff}\u{5230} access_key"
        } else {
            loginMessage = "\u{77ed}\u{4fe1}\u{767b}\u{5f55}\u{6210}\u{529f}，App \u{7aef}\u{63a8}\u{8350}\u{4f1a}\u{66f4}\u{63a5}\u{8fd1}\u{5b98}\u{65b9}\u{5ba2}\u{6237}\u{7aef}。"
        }
        await refreshUser()
    }

    private func pollQRCodeLogin(_ info: QRCodeLoginInfo) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }

            do {
                let result = try await api.pollAppQRCodeLogin(authCode: info.qrcodeKey)
                switch result.status {
                case .waitingForScan:
                    if case .waiting = qrLoginState {
                        break
                    }
                    qrLoginState = .waiting(info, result.message ?? "\u{8bf7}\u{4f7f}\u{7528} B \u{7ad9}\u{5ba2}\u{6237}\u{7aef}\u{626b}\u{7801}")
                case .waitingForConfirm:
                    qrLoginState = .scanned(info, result.message ?? "\u{5df2}\u{626b}\u{7801}，\u{8bf7}\u{5728}\u{624b}\u{673a}\u{4e0a}\u{786e}\u{8ba4}")
                case .expired:
                    qrLoginState = .expired(result.message ?? "\u{4e8c}\u{7ef4}\u{7801}\u{5df2}\u{8fc7}\u{671f}")
                    return
                case .confirmed:
                    guard let loginData = result.loginData else {
                        qrLoginState = .failed("\u{767b}\u{5f55}\u{6210}\u{529f}\u{4f46}\u{6ca1}\u{6709}\u{62ff}\u{5230}\u{79fb}\u{52a8}\u{7aef}\u{51ed}\u{8bc1}，\u{8bf7}\u{6539}\u{7528}\u{7f51}\u{9875}\u{767b}\u{5f55}。")
                        return
                    }
                    let cookieValues = loginData.loginCookieValues
                    guard !cookieValues.isEmpty else {
                        qrLoginState = .failed("\u{767b}\u{5f55}\u{6210}\u{529f}\u{4f46}\u{6ca1}\u{6709}\u{62ff}\u{5230} Cookie，\u{8bf7}\u{6539}\u{7528}\u{7f51}\u{9875}\u{767b}\u{5f55}。")
                        return
                    }
                    try sessionStore.saveLoginCookies(cookieValues, credentialKind: .appQRCodeTV)
                    guard sessionStore.isLoggedIn else {
                        qrLoginState = .failed("\u{767b}\u{5f55}\u{6210}\u{529f}\u{4f46}\u{6ca1}\u{6709}\u{62ff}\u{5230} Cookie，\u{8bf7}\u{6539}\u{7528}\u{7f51}\u{9875}\u{767b}\u{5f55}。")
                        return
                    }
                    if sessionStore.appAccessKey() == nil {
                        loginMessage = "\u{767b}\u{5f55}\u{6210}\u{529f}，\u{4f46}\u{6ca1}\u{6709}\u{62ff}\u{5230} access_key"
                        qrLoginState = .succeeded("\u{767b}\u{5f55}\u{6210}\u{529f}，\u{4f46}\u{79fb}\u{52a8}\u{7aef}\u{51ed}\u{8bc1}\u{7f3a}\u{5931}")
                    } else {
                        loginMessage = "\u{626b}\u{7801}\u{767b}\u{5f55}\u{6210}\u{529f}；\u{5982} App \u{7aef}\u{63a8}\u{8350}\u{4e0d}\u{51c6}，\u{53ef}\u{6539}\u{7528}\u{77ed}\u{4fe1}\u{767b}\u{5f55}\u{6216}\u{7f51}\u{9875}\u{7aef}\u{63a8}\u{8350}。"
                        qrLoginState = .succeeded("\u{626b}\u{7801}\u{767b}\u{5f55}\u{6210}\u{529f}")
                    }
                    await refreshUser()
                    return
                case .unknown(let code):
                    let message = result.message ?? "\u{672a}\u{77e5}\u{72b6}\u{6001}"
                    qrLoginState = .waiting(info, "\(message) (\(code))")
                }
            } catch {
                if !Task.isCancelled, !Self.isTransientQRCodePollingError(error) {
                    qrLoginState = .waiting(info, error.localizedDescription)
                }
            }
        }
    }

    private nonisolated static func normalizedPhone(_ value: String) -> String {
        value
            .filter { $0.isNumber }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func normalizedCountryCode(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        return digits.isEmpty ? "86" : digits
    }

    private nonisolated static func isTransientQRCodePollingError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        let code = URLError.Code(rawValue: nsError.code)
        switch code {
        case .networkConnectionLost, .notConnectedToInternet, .timedOut, .cancelled:
            return true
        default:
            return false
        }
    }

    private func resetAccountLibraryState() {
        statistics = nil; statisticsCredentialVersion = nil
        favoritesGeneration = UUID(); favoritesCredentialVersion = nil
        accountHistory = []
        accountFavorites = []
        accountWatchLater = []
        favoriteFolders = []
        favoriteFolderEntries = [:]
        favoriteFolderEntryStates = [:]
        historyLoadMoreState = .idle
        historyHasMore = false
        historyCursor = nil
        favoriteFolderLoadMoreStates = [:]
        favoriteFolderHasMore = [:]
        favoriteFolderPages = [:]
        historyState = .idle
        favoriteState = .idle
        watchLaterState = .idle; watchLaterLoadMoreState = .idle; watchLaterHasMore = false
        watchLaterGeneration = UUID(); watchLaterCredentialVersion = nil; watchLaterRequestCredentialVersion = nil
        watchLaterPage = 1; watchLaterFilter = PiliWatchLaterFilter(); appliedWatchLaterFilter = PiliWatchLaterFilter()
    }

    private nonisolated static func uniqued(_ entries: [AccountVideoEntry]) -> [AccountVideoEntry] {
        appendingUnique(entries, to: [])
    }

    private nonisolated static func appendingUnique(
        _ newEntries: [AccountVideoEntry],
        to existingEntries: [AccountVideoEntry]
    ) -> [AccountVideoEntry] {
        var result = existingEntries
        var seen = Set(existingEntries.map(\.id))
        for entry in newEntries where seen.insert(entry.id).inserted {
            result.append(entry)
        }
        return result
    }
}

enum QRCodeLoginState: Equatable {
    case idle
    case loading
    case waiting(QRCodeLoginInfo, String)
    case scanned(QRCodeLoginInfo, String)
    case expired(String)
    case succeeded(String)
    case failed(String)

    var codeInfo: QRCodeLoginInfo? {
        switch self {
        case .waiting(let info, _), .scanned(let info, _):
            return info
        default:
            return nil
        }
    }

    var message: String {
        switch self {
        case .idle:
            return ""
        case .loading:
            return "\u{6b63}\u{5728}\u{751f}\u{6210}\u{4e8c}\u{7ef4}\u{7801}"
        case .waiting(_, let message), .scanned(_, let message), .expired(let message), .succeeded(let message), .failed(let message):
            return message
        }
    }
}
