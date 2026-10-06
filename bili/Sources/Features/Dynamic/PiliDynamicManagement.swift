import SwiftUI
import Translation
import UIKit

extension Notification.Name {
    static let piliDynamicChanged = Notification.Name("PiliDynamicChanged")
}

extension PiliDynamicDraft {
    nonisolated static func editing(_ item: DynamicFeedItem) -> Self {
        var value = Self(); value.editingID = item.idStr
        if item.isForward { value.repostID = item.original?.idStr }
        value.tokens = item.textSegments.map { segment in
            switch segment {
            case .text(let text): return .init(text: text)
            case .emoji(let text, _): return .init(text: text, type: 9)
            case .mention(let text, let mid, _): return .init(text: text, type: mid == nil ? 1 : 2, businessID: mid.map(String.init) ?? "")
            case .link(let title, let url): return .init(text: title == url ? url : "\(title) \(url)")
            }
        }
        value.pictures = item.imageItems.map { .init(url: $0.url.normalizedBiliURL(), width: $0.width ?? 1, height: $0.height ?? 1) }
        return value
    }
}

struct PiliDynamicManagementModifier: ViewModifier {
    let item: DynamicFeedItem
    let api: BiliAPIClient
    @State private var composer: ComposerRoute?
    @State private var showsReport = false
    @State private var showsExport = false
    @State private var showsTranslation = false
    @State private var checksVisibility = false
    @State private var confirmDelete = false
    @State private var message: String?
    @State private var busy = false
    @State private var operationIdentity: PiliAccountIdentity?
    private struct ComposerRoute: Identifiable { let id = UUID(); let draft: PiliDynamicDraft }
    func body(content: Content) -> some View {
        content.contextMenu {
            Button("转发动态", systemImage: "arrowshape.turn.up.right") { var draft = PiliDynamicDraft(); draft.repostID = item.idStr; composer = .init(draft: draft) }
            Button("复制动态文字", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.displayText ?? "" }
            Button("翻译动态", systemImage: "translate") { showsTranslation = true }
            Button("保存完整动态", systemImage: "square.and.arrow.down") { showsExport = true }
            Button("举报动态", systemImage: "exclamationmark.bubble") { showsReport = true }
            if item.author?.mid == api.requestSnapshot(purpose: .main).currentUserMID {
                Button("检查对外可见性", systemImage: "checkmark.shield") { checksVisibility = true }
                if ["DYNAMIC_TYPE_WORD", "DYNAMIC_TYPE_DRAW", "DYNAMIC_TYPE_FORWARD"].contains(item.type ?? "") {
                    Button("编辑动态", systemImage: "square.and.pencil") { loadEditingDraft() }.disabled(busy)
                }
                Button("置顶动态", systemImage: "pin") { mutate("set_top") }
                Button("取消置顶", systemImage: "pin.slash") { mutate("rm_top") }
                Button("删除动态", systemImage: "trash", role: .destructive) {
                    operationIdentity = PiliAccountIdentity(api.requestSnapshot(purpose: .main)); confirmDelete = true
                }
            }
        }
        .sheet(item: $composer) { route in
            PiliDynamicComposer(api: api, initial: route.draft) { NotificationCenter.default.post(name: .piliDynamicChanged, object: nil) }
        }
        .sheet(isPresented: $showsReport) {
            NavigationStack { PiliContentReportView(api: api, target: .dynamic(id: item.idStr, author: item.author?.mid ?? 0)) }
        }
        .translationPresentation(isPresented: $showsTranslation, text: item.displayText ?? "")
        .sheet(isPresented: $showsExport) { PiliDynamicExportView(api: api, id: item.idStr) }
        .sheet(isPresented: $checksVisibility) { NavigationStack { PiliVisibilityCheckView(api: api, target: .dynamic(item.idStr)) } }
        .confirmationDialog("删除这条动态？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { mutate("remove", identity: operationIdentity) }
        }
        .alert("动态操作", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(message ?? "") }
    }
    private func loadEditingDraft() {
        guard !busy else { return }; busy = true
        let account = PiliAccountIdentity(api.requestSnapshot(purpose: .main))
        Task {
            defer { busy = false }
            do { composer = .init(draft: try await api.piliEditingDraft(id: item.idStr, identity: account)) }
            catch { message = error.localizedDescription }
        }
    }
    private func mutate(_ action: String, identity: PiliAccountIdentity? = nil) {
        guard !busy else { return }
        let account = identity ?? PiliAccountIdentity(api.requestSnapshot(purpose: .main))
        busy = true
        Task {
            defer { busy = false }
            do {
                try await api.managePiliDynamic(id: item.idStr, action: action, identity: account)
                message = "操作成功"; NotificationCenter.default.post(name: .piliDynamicChanged, object: nil)
            } catch { message = error.localizedDescription }
        }
    }
}

struct PiliDynamicSearchView: View {
    let api: BiliAPIClient
    let mid: Int
    @State private var query = ""
    @State private var submitted = ""
    @State private var items: [DynamicFeedItem] = []
    @State private var offset = ""
    @State private var pageNumber = 1
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    @State private var generation = UUID()
    var body: some View {
        ScrollView {
            LazyVStack {
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(items) { item in DynamicFeedCard(item: item, api: api).padding(.horizontal) }
                if loading { ProgressView() }
                else if hasMore { Button("加载更多") { Task { await load(reset: false) } } }
                else if !submitted.isEmpty && items.isEmpty { ContentUnavailableView.search(text: submitted) }
            }
        }.navigationTitle("搜索用户动态").searchable(text: $query, prompt: "关键词")
            .onSubmit(of: .search) { submitted = query; Task { await load(reset: true) } }
    }
    private func load(reset: Bool) async {
        if reset { generation = UUID(); items = []; offset = ""; pageNumber = 1 }
        else if loading { return }
        guard !submitted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let token = generation, text = submitted
        loading = true; error = nil
        defer { if token == generation { loading = false } }
        do {
            let page = try await api.fetchPiliDynamicSearch(mid: mid, keyword: text, offset: offset, page: pageNumber)
            guard token == generation, !Task.isCancelled else { return }
            var seen = Set(items.map(\.id)); items.append(contentsOf: (page.items ?? []).filter { seen.insert($0.id).inserted })
            let next = page.offset ?? ""; hasMore = page.hasMore == true && !next.isEmpty && next != offset; offset = next
            pageNumber += 1
        } catch { if token == generation { self.error = error.localizedDescription } }
    }
}
