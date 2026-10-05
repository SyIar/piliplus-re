import Combine
import Foundation

extension BiliAPIClient {
    @MainActor func commentPageForCurrentWriter(_ page: CommentPage, usesDefaultReader: Bool) -> CommentPage {
        guard usesDefaultReader,
              requestSnapshot(purpose: .commentRead).currentUserMID != requestSnapshot(purpose: .interaction).currentUserMID else { return page }
        return CommentPage(replies: page.replies?.map { $0.removingReaderReactions() },
                           topReplies: page.topReplies?.map { $0.removingReaderReactions() },
                           root: page.root?.removingReaderReactions(), cursor: page.cursor)
    }

    @MainActor var commentReadRevision: Int {
        sessionStore.accountConfigurationVersion &* 2 &+ (libraryStore.multiAccountExperimentEnabled ? 1 : 0)
    }

    @MainActor var commentAccountChanges: AnyPublisher<Void, Never> {
        Publishers.CombineLatest(sessionStore.$accountConfigurationVersion, libraryStore.$multiAccountExperimentEnabled)
            .dropFirst().receive(on: RunLoop.main).map { _ in () }.eraseToAnyPublisher()
    }
}
