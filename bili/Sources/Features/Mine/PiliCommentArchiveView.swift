import SwiftUI
import UniformTypeIdentifiers

private struct PiliCommentDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct PiliCommentArchiveView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var identity: PiliAccountIdentity?
    @State private var items: [PiliSavedComment] = []
    @State private var query = ""
    @State private var importing = false
    @State private var exporting = false
    @State private var document = PiliCommentDocument(data: Data())
    @State private var deleting: PiliSavedComment?
    @State private var comments: DynamicFeedItem?
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        List {
            Section {
                Text("保存在本机的已发送评论，可导入原版 PiliPlus 导出的 JSON。最多保留最近 2,000 条；不会自动获取账号的全部历史评论。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let message { Text(message).font(.footnote) }
            }
            ForEach(items.filter { query.isEmpty || $0.message.localizedCaseInsensitiveContains(query) }) { comment in
                VStack(alignment: .leading, spacing: 8) {
                    Text(comment.message).textSelection(.enabled)
                    Text(Date(timeIntervalSince1970: Double(comment.created)), style: .date).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        if let url = comment.contextURL { AppLinkButton(url: url) { Label("查看内容", systemImage: "arrow.up.right") } }
                        Button("评论区") { comments = try? piliCommentTarget(oid: comment.oid, type: comment.type) }
                        Spacer()
                        Menu("更多", systemImage: "ellipsis") {
                            Button("检查评论可见性") { check(comment) }
                            Button("仅移除本机记录") { remove(comment, server: false) }
                            Button("删除已发送评论", role: .destructive) { deleting = comment }
                        }
                    }.font(.caption).buttonStyle(.borderless).disabled(busy)
                }.padding(.vertical, 5)
            }
            if busy { ProgressView() }
            else if items.isEmpty { ContentUnavailableView("暂无本机评论", systemImage: "text.bubble", description: Text("发送成功的评论将自动保存在这里。")) }
        }.navigationTitle("我的评论").searchable(text: $query, prompt: "搜索评论内容")
            .task(id: sessionStore.interactionAccountCredentialVersion) { await reload() }
            .toolbar { Menu("备份", systemImage: "ellipsis.circle") {
                Button("导入评论") { importing = true }.disabled(identity == nil || busy)
                Button("导出评论") { Task { await export() } }.disabled(identity == nil || busy)
            } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                Task { await importFile(result) }
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "PiliPlus-comments") { result in
                if case .failure(let error) = result { message = error.localizedDescription }
            }
            .sheet(item: $comments) { DynamicCommentsSheet(item: $0, api: dependencies.api) }
            .confirmationDialog("从哔哩哔哩删除这条评论？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                if let deleting { Button("删除评论", role: .destructive) { remove(deleting, server: true) } }
            }
    }
    private func reload() async {
        let context = await dependencies.api.requestSnapshot(purpose: .interaction)
        guard context.isLoggedIn else { identity = nil; items = []; message = "请先登录互动账号"; return }
        let current = PiliAccountIdentity(context); identity = current; items = []
        do {
            let values = try await PiliCommentArchive.shared.comments(account: current.mid)
            guard identity == current else { return }; items = values
        } catch { message = error.localizedDescription }
    }
    private func export() async {
        guard let identity else { return }
        do { document = .init(data: try await PiliCommentArchive.shared.export(account: identity.mid)); exporting = true }
        catch { message = error.localizedDescription }
    }
    private func importFile(_ result: Result<URL, Error>) async {
        guard let identity, !busy else { return }; busy = true; defer { busy = false }
        do { let count = try await PiliCommentArchive.shared.importFile(result.get(), account: identity.mid); message = "已导入 \(count) 条评论"; await reload() }
        catch { message = error.localizedDescription }
    }
    private func remove(_ comment: PiliSavedComment, server: Bool) {
        guard !busy, let identity, comment.account == identity.mid else { return }; busy = true
        Task {
            defer { busy = false; deleting = nil }
            do {
                if server { try await dependencies.api.mutatePiliComment(.delete, oid: comment.oid, type: comment.type, rpid: comment.id, identity: identity, referer: comment.contextURL?.absoluteString ?? "https://www.bilibili.com/") }
                try await PiliCommentArchive.shared.remove(id: comment.id, account: comment.account)
                if self.identity == identity { items.removeAll { $0.id == comment.id } }
            } catch { message = error.localizedDescription }
        }
    }
    private func check(_ comment: PiliSavedComment) {
        guard let identity else { return }
        Task {
            do {
                let result = try await dependencies.api.piliCheckVisibility(.comment(oid: comment.oid, type: comment.type, id: comment.id, root: comment.root), identity: identity)
                if self.identity == identity { message = result.message }
            } catch { message = error.localizedDescription }
        }
    }
}
