import Foundation

extension HomeViewModel {
    func refreshFromUserPull() async {
        let isModeSwitchRefresh = modeSwitchRefreshPending
        modeSwitchRefreshPending = false

        guard isModeSwitchRefresh || !isRefreshing else { return }
        if !isModeSwitchRefresh {
            let now = Date()
            if let lastUserRefreshDate,
               now.timeIntervalSince(lastUserRefreshDate) < 1.0 {
                return
            }
            lastUserRefreshDate = now
        }
        // Refresh the shared snapshot once per TTL, independently of card rendering.
        async let blacklist: Void = PiliBlacklistedCreators.shared.refresh(api: pageCoordinator.api)
        isUserRefreshing = true
        defer {
            isUserRefreshing = false
        }
        if isModeSwitchRefresh {
            await refresh(resetCursor: true)
        } else {
            await refresh(preservingExistingRecommendations: true)
        }
        await blacklist
    }
}
