import Foundation

/// The existing composer delegates posting/refreshing to several hosts. Carry
/// the immutable account and mention metadata through that asynchronous call
/// tree, without storing per-draft state on the shared API client.
nonisolated struct PiliCommentSubmissionScope: Sendable {
    let identity: PiliAccountIdentity
    let mentions: [String: Int]
    @TaskLocal static var current: Self? = nil
}
