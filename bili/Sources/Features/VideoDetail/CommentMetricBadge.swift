import SwiftUI
import ChunUI

nonisolated struct CommentLikeDisplayState: Equatable, Sendable {
    let isLiked: Bool
    let likeCount: Int

    func toggled() -> Self {
        Self(
            isLiked: !isLiked,
            likeCount: max(0, likeCount + (isLiked ? -1 : 1))
        )
    }
}

struct CommentLikeTarget: Equatable, Sendable {
    let oid: String
    let type: Int
    let referer: String

    init?(oid: String?, type: Int?, referer: String) {
        guard let oid = oid?.trimmingCharacters(in: .whitespacesAndNewlines),
              !oid.isEmpty,
              let type,
              type > 0
        else {
            return nil
        }
        self.oid = oid
        self.type = type
        self.referer = referer
    }
}

private struct CommentLikeTargetKey: EnvironmentKey {
    static let defaultValue: CommentLikeTarget? = nil
}

extension EnvironmentValues {
    var commentLikeTarget: CommentLikeTarget? {
        get { self[CommentLikeTargetKey.self] }
        set { self[CommentLikeTargetKey.self] = newValue }
    }
}

extension View {
    func commentLikeTarget(oid: String?, type: Int?, referer: String) -> some View {
        environment(
            \.commentLikeTarget,
            CommentLikeTarget(oid: oid, type: type, referer: referer)
        )
    }
}

struct CommentMetricBadge: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let text: String
    let systemImage: String
    let isHighlighted: Bool

    var body: some View {
        PiliLabel(text, systemImage: systemImage)
            .piliFont(.sm).fontWeight(.semibold)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(isHighlighted ? appTintColor : .secondary)
            .frame(height: 24)
    }
}

struct CommentLikeButton: View {
    @Environment(\.commentLikeTarget) private var target
    @EnvironmentObject private var dependencies: AppDependencies
    let comment: Comment

    var body: some View {
        if let target {
            PiliCommentAccountContext(sessionStore: dependencies.sessionStore, libraryStore: dependencies.libraryStore) { identity in
                let subject = PiliCommentActionStore.Subject(identity: identity, oid: target.oid, type: target.type)
                PiliCommentLikeControl(comment: comment, target: target, subject: subject,
                                       store: dependencies.commentActions, api: dependencies.api)
                    .id(subject)
            }
        } else {
            CommentMetricBadge(text: BiliFormatters.compactCount(comment.like), systemImage: "hand.thumbsup", isHighlighted: false)
        }
    }
}

private struct PiliCommentLikeControl: View {
    let comment: Comment
    let target: CommentLikeTarget
    let subject: PiliCommentActionStore.Subject
    @ObservedObject var store: PiliCommentActionStore
    let api: BiliAPIClient
    @State private var errorMessage: String?

    var body: some View {
        let state = store.state(comment, subject: subject)
        Button {
            Task {
                do {
                    try await store.perform(.like(state.reaction != 1), comment: comment, subject: subject, referer: target.referer, api: api)
                    Haptics.success()
                } catch { errorMessage = error.localizedDescription }
            }
        } label: {
            CommentMetricBadge(text: BiliFormatters.compactCount(state.likeCount),
                               systemImage: state.reaction == 1 ? "hand.thumbsup.fill" : "hand.thumbsup",
                               isHighlighted: state.reaction == 1)
        }
        .buttonStyle(.plain)
        .disabled(store.isBusy(subject) || state.deleted)
        .accessibilityLabel(state.reaction == 1 ? "取消点赞评论" : "点赞评论")
        .accessibilityValue("\(state.likeCount) 个赞")
        .piliAlert("评论操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            PiliAlertButton("好", role: .cancel) { errorMessage = nil }
        } message: { errorMessage ?? "" }
        .dynamicCommentHitArea(.control)
    }
}
