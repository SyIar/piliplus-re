import Combine
import Foundation

nonisolated struct PiliCommentState: Equatable {
    var reaction: Int
    var likeCount: Int
    var deleted = false

    init(comment: Comment) {
        reaction = comment.likeState ?? 0
        likeCount = max(0, comment.like ?? 0)
    }

    mutating func apply(_ action: PiliCommentMutation) {
        let wasLiked = reaction == 1
        switch action {
        case .like(let enabled): reaction = enabled ? 1 : 0
        case .dislike(let enabled): reaction = enabled ? 2 : 0
        case .delete: deleted = true
        default: return
        }
        if wasLiked != (reaction == 1) { likeCount = max(0, likeCount + (reaction == 1 ? 1 : -1)) }
    }
}

nonisolated struct PiliCommentPermissions: Equatable {
    let canDelete: Bool
    let canPin: Bool
    init(comment: Comment, accountMID: Int, ownerMID: Int?) {
        let ownsContent = accountMID > 0 && accountMID == ownerMID
        canDelete = accountMID > 0 && (ownsContent || comment.member?.mid.flatMap(Int.init) == accountMID)
        canPin = ownsContent && (comment.rootID ?? 0) == 0
    }
}

@MainActor
final class PiliCommentActionStore: ObservableObject {
    struct Subject: Hashable {
        let identity: PiliAccountIdentity
        let oid: String
        let type: Int
    }
    struct Key: Hashable {
        let subject: Subject
        let rpid: Int
    }
    @Published private var states: [Key: PiliCommentState] = [:]
    @Published private var busy: Set<Subject> = []
    @Published private var pinned: [Subject: Int] = [:]

    func state(_ comment: Comment, subject: Subject) -> PiliCommentState {
        var result = states[Key(subject: subject, rpid: comment.rpid)] ?? PiliCommentState(comment: comment)
        if let root = comment.rootID, root > 0, states[Key(subject: subject, rpid: root)]?.deleted == true { result.deleted = true }
        return result
    }
    func isBusy(_ subject: Subject) -> Bool { busy.contains(subject) }
    func isPinned(_ comment: Comment, subject: Subject) -> Bool {
        pinned[subject].map { $0 == comment.rpid } ?? comment.isPinnedByOwner
    }
    func perform(_ action: PiliCommentMutation, comment: Comment, subject: Subject, referer: String, api: BiliAPIClient) async throws {
        guard !busy.contains(subject) else { throw PiliOfflineError.message("评论操作正在进行，请稍后重试") }
        busy.insert(subject)
        defer { busy.remove(subject) }
        let key = Key(subject: subject, rpid: comment.rpid)
        var value = state(comment, subject: subject)
        try await api.mutatePiliComment(action, oid: subject.oid, type: subject.type, rpid: comment.rpid,
                                        identity: subject.identity, referer: referer)
        guard subject.identity.matches(api.requestSnapshot(purpose: .interaction)) else {
            throw PiliOfflineError.message("互动账号已切换，请刷新评论")
        }
        value.apply(action)
        states[key] = value
        switch action {
        case .pin(let enabled): pinned[subject] = enabled ? comment.rpid : 0
        case .delete:
            if pinned[subject] == comment.rpid { pinned[subject] = 0 }
        default: return
        }
        NotificationCenter.default.post(name: .piliCommentModerated, object: subject)
    }
}

extension Notification.Name {
    static let piliCommentModerated = Notification.Name("piliplus.comment.moderated")
}
