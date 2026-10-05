import Combine
import Foundation

extension BiliAPIClient {
    @MainActor var commentReadRevision: Int {
        sessionStore.accountConfigurationVersion &* 2 &+ (libraryStore.multiAccountExperimentEnabled ? 1 : 0)
    }

    @MainActor var commentAccountChanges: AnyPublisher<Void, Never> {
        Publishers.CombineLatest(sessionStore.$accountConfigurationVersion, libraryStore.$multiAccountExperimentEnabled)
            .dropFirst().receive(on: RunLoop.main).map { _ in () }.eraseToAnyPublisher()
    }
}
