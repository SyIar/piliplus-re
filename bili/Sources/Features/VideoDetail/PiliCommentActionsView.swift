import SwiftUI

private struct PiliCommentActionsModifier: ViewModifier {
    let comment: Comment
    @Environment(\.commentLikeTarget) private var target
    @Environment(\.commentContentOwnerMID) private var ownerMID
    @EnvironmentObject private var dependencies: AppDependencies

    func body(content: Content) -> some View {
        if let target {
            PiliCommentAccountContext(sessionStore: dependencies.sessionStore, libraryStore: dependencies.libraryStore) { identity in
                let subject = PiliCommentActionStore.Subject(identity: identity, oid: target.oid, type: target.type)
                PiliCommentActionsContent(content: content, comment: comment, subject: subject, target: target,
                                          ownerMID: ownerMID, store: dependencies.commentActions, api: dependencies.api)
                    .id(subject)
            }
        } else {
            content.commentCopyContextMenu(text: comment.content?.message, title: "复制评论")
        }
    }
}

extension View {
    func piliCommentActions(_ comment: Comment) -> some View {
        modifier(PiliCommentActionsModifier(comment: comment))
    }

    func onPiliCommentModerated(oid: String?, type: Int?, refresh: @escaping () async -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .piliCommentModerated)) { event in
            guard let subject = event.object as? PiliCommentActionStore.Subject,
                  subject.oid == oid, subject.type == type else { return }
            Task { await refresh() }
        }
    }
}

private struct PiliCommentActionsContent<Content: View>: View {
    let content: Content
    let comment: Comment
    let subject: PiliCommentActionStore.Subject
    let target: CommentLikeTarget
    let ownerMID: Int?
    @ObservedObject var store: PiliCommentActionStore
    let api: BiliAPIClient
    @State private var pending: PiliCommentMutation?
    @State private var showsReport = false
    @State private var showsExport = false
    @State private var errorMessage: String?
    private var state: PiliCommentState { store.state(comment, subject: subject) }
    private var permissions: PiliCommentPermissions { .init(comment: comment, accountMID: subject.identity.mid, ownerMID: ownerMID) }

    var body: some View {
        Group {
            if state.deleted {
                Label("评论已删除", systemImage: "text.bubble")
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if store.isPinned(comment, subject: subject) {
                        Label("UP 主置顶", systemImage: "pin.fill").font(.caption2).foregroundStyle(.secondary)
                    }
                    content
                }
                .contextMenu {
                    Button { CommentCopyAction.copy(comment.content?.message ?? "") } label: { Label("复制评论", systemImage: "doc.on.doc") }
                    Button("保存完整评论", systemImage: "square.and.arrow.down") { showsExport = true }
                    Button { perform(.dislike(state.reaction != 2)) } label: {
                        Label(state.reaction == 2 ? "取消点踩" : "点踩", systemImage: state.reaction == 2 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    }
                    .disabled(store.isBusy(subject))
                    if permissions.canPin {
                        Button { pending = .pin(!store.isPinned(comment, subject: subject)) } label: {
                            Label(store.isPinned(comment, subject: subject) ? "取消置顶" : "置顶评论", systemImage: "pin")
                        }
                        .disabled(store.isBusy(subject))
                    }
                    if permissions.canDelete {
                        Button(role: .destructive) { pending = .delete } label: { Label("删除评论", systemImage: "trash") }
                            .disabled(store.isBusy(subject))
                    }
                    Button { showsReport = true } label: { Label("举报评论", systemImage: "exclamationmark.bubble") }
                        .disabled(store.isBusy(subject))
                }
            }
        }
        .confirmationDialog(pending == .delete ? "删除这条评论？" : "更改评论置顶状态？",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            if let action = pending {
                Button(action == .delete ? "删除" : "确认", role: action == .delete ? .destructive : nil) {
                    pending = nil
                    perform(action)
                }
            }
            Button("取消", role: .cancel) { pending = nil }
        } message: {
            Text(pending == .delete ? "删除后无法恢复。" : "置顶新的评论会替换当前置顶评论。")
        }
        .sheet(isPresented: $showsReport) {
            PiliCommentReportSheet { reason, text in
                try await store.perform(.report(reason: reason, text: text), comment: comment, subject: subject, referer: target.referer, api: api)
            }
        }
        .sheet(isPresented: $showsExport) { PiliContentImageExportView(document: .comment(comment, source: target.referer)) }
        .alert("评论操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func perform(_ action: PiliCommentMutation) {
        Task {
            do { try await store.perform(action, comment: comment, subject: subject, referer: target.referer, api: api) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct PiliCommentReportSheet: View {
    let submit: (Int, String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reasonID = 1
    @State private var text = ""
    @State private var submitting = false
    @State private var didSubmit = false
    @State private var errorMessage: String?
    private var valid: Bool {
        text.count <= 1_000 && (!(reasonID == 0 || reasonID == 22) || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    var body: some View {
        NavigationStack {
            Form {
                if didSubmit {
                    Label("举报已提交", systemImage: "checkmark.circle").foregroundStyle(.green)
                } else {
                    Picker("举报原因", selection: $reasonID) {
                        ForEach(PiliCommentReportReason.all) { Text($0.title).tag($0.id) }
                    }
                    Section("补充说明\(reasonID == 0 || reasonID == 22 ? "（必填）" : "（选填）")") {
                        TextField("说明具体问题", text: $text, axis: .vertical).lineLimit(3...6)
                        Text("\(text.count)/1000").font(.caption).foregroundStyle(.secondary)
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .disabled(submitting)
            .navigationTitle("举报评论").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(didSubmit ? "完成" : "取消") { dismiss() }.disabled(submitting) }
                ToolbarItem(placement: .confirmationAction) {
                    if !didSubmit {
                        Button("提交") {
                            submitting = true
                            Task {
                                defer { submitting = false }
                                do { try await submit(reasonID, text); didSubmit = true }
                                catch { errorMessage = error.localizedDescription }
                            }
                        }.disabled(!valid || submitting)
                    }
                }
            }
        }
        .interactiveDismissDisabled(submitting)
    }
}

struct PiliCommentAccountContext<Content: View>: View {
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var libraryStore: LibraryStore
    @ViewBuilder let content: (PiliAccountIdentity) -> Content
    var body: some View {
        let account = sessionStore.credentialSnapshot(for: .interaction, multiAccountEnabled: libraryStore.multiAccountExperimentEnabled)
        content(.init(mid: account.accountMID ?? 0, version: account.version))
    }
}
