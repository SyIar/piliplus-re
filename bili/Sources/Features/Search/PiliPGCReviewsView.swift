import SwiftUI
import ChunUI

struct PiliPGCReviewsView: View {
    let api: BiliAPIClient
    let mediaID: Int
    let title: String
    @PiliDismiss private var dismiss
    @State private var isLong = false
    @State private var latest = false
    @State private var reviews: [PiliPGCReview] = []
    @State private var cursor: String?
    @State private var more = true
    @State private var loading = false
    @State private var busy = false
    @State private var generation = UUID()
    @State private var identity: PiliAccountIdentity?
    @State private var error: String?
    @State private var editor: ReviewDraft?
    @State private var deleting: PiliPGCReview?
    private struct ReviewDraft: Identifiable {
        let id = UUID()
        let review: PiliPGCReview?
    }
    var body: some View {
        PiliList {
            Section {
                Picker("类型", selection: $isLong) { Text("短评").tag(false); Text("长评").tag(true) }.pickerStyle(.segmented)
                Toggle("最新优先", isOn: $latest)
                if !isLong { PiliIconButton("写短评与评分", systemImage: "square.and.pencil") { editor = .init(review: nil) }.disabled(identity?.mid == 0 || identity == nil) }
            }
            if let error { Text(error); Button("重试") { Task { await load(reset: reviews.isEmpty) } } }
            ForEach(reviews) { review in row(review) }
            if loading { ProgressView() }
            else if more { Button("加载更多") { Task { await load() } } }
            else if reviews.isEmpty { Text("暂无点评") }
        }.disabled(busy).navigationTitle(title + " · 点评").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(busy) } }
            .task(id: "\(isLong)-\(latest)") { if identity == nil { identity = .init(api.requestSnapshot()) }; await load(reset: true) }
            .piliSheet(item: $editor) { draft in
                if let identity {
                    PiliPGCReviewEditor(api: api, mediaID: mediaID, identity: identity, review: draft.review) { Task { await load(reset: true) } }
                }
            }
            .piliConfirmation("删除短评，同时删除评分？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                if let review = deleting { PiliAlertButton("删除", role: .destructive) { mutate(.delete(review.id)) }; PiliAlertButton("取消", role: .cancel) { deleting = nil } }
            }
    }
    private func row(_ review: PiliPGCReview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VideoOwnerRouteLink(owner: review.author) { Text(review.author.name).font(.cc.baseBold) }
            Text("\(review.score) 分 · \(review.date)").font(.cc.sm).foregroundStyle(.secondary)
            if !review.title.isEmpty { Text(review.title).font(.cc.baseBold) }
            Text(review.text).textSelection(.enabled)
            if isLong, review.articleID > 0, let url = URL(string: "https://www.bilibili.com/read/cv\(review.articleID)") {
                AppLinkButton(url: url) { PiliLabel("阅读长评", systemImage: "doc.text") }
            } else if !isLong {
                HStack {
                    PiliIconButton("\(review.likes)", systemImage: review.liked ? "hand.thumbsup.fill" : "hand.thumbsup") { mutate(.like(review.id)) }
                    PiliIconButton("点踩", systemImage: review.disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown") { mutate(.dislike(review.id)) }
                    Spacer()
                    Menu("更多", systemImage: "ellipsis") {
                        if review.author.mid == identity?.mid {
                            Button("编辑") { editor = .init(review: review) }
                            Button("删除", role: .destructive) { deleting = review }
                        }
                        NavigationLink {
                            PiliAccountWebView(api: api, url: URL(string: "https://www.bilibili.com/appeal/?reviewId=\(review.id)&type=shortComment&mediaId=\(mediaID)")!, title: "举报点评")
                        } label: { Text("举报") }
                    }
                }.buttonStyle(.borderless).font(.cc.sm)
            }
        }.padding(.vertical, 6)
    }
    private func load(reset: Bool = false) async {
        if reset { generation = UUID(); reviews = []; cursor = nil; more = true }
        else if loading || !more { return }
        let ticket = generation, next = cursor; loading = true; error = nil
        defer { if generation == ticket { loading = false } }
        do {
            let result = try await api.piliPGCReviews(mediaID: mediaID, long: isLong, latest: latest, cursor: next)
            guard !Task.isCancelled, generation == ticket else { return }
            var seen = Set(reviews.map(\.id)); let incoming = result.items.filter { seen.insert($0.id).inserted }
            reviews.append(contentsOf: incoming); cursor = result.next
            more = result.next != nil && result.next != next && !incoming.isEmpty && (result.total.map { reviews.count < $0 } ?? true)
        } catch { if !Task.isCancelled, generation == ticket { self.error = error.localizedDescription } }
    }
    private func mutate(_ action: PiliPGCReviewMutation) {
        guard !busy, let identity else { return }; busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                try await api.piliMutatePGCReview(mediaID: mediaID, action: action, identity: identity)
                guard identity.matches(api.requestSnapshot()) else { throw PiliOfflineError.message("账号已切换") }
                switch action {
                case .delete(let id): reviews.removeAll { $0.id == id }
                case .like(let id), .dislike(let id):
                    if let index = reviews.firstIndex(where: { $0.id == id }) {
                        let old = reviews[index]
                        if case .like = action {
                            reviews[index].liked.toggle(); reviews[index].likes = max(0, old.likes + (old.liked ? -1 : 1))
                            if !old.liked { reviews[index].disliked = false }
                        } else {
                            reviews[index].disliked.toggle()
                            if !old.disliked { reviews[index].liked = false; reviews[index].likes = max(0, old.likes - (old.liked ? 1 : 0)) }
                        }
                    }
                default: break
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct PiliPGCReviewEditor: View {
    let api: BiliAPIClient
    let mediaID: Int
    let identity: PiliAccountIdentity
    let review: PiliPGCReview?
    let onSave: () -> Void
    @PiliDismiss private var dismiss
    @State private var score = 10
    @State private var content = ""
    @State private var share = false
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            PiliForm {
                Picker("评分", selection: $score) { ForEach([2, 4, 6, 8, 10], id: \.self) { Text("\($0) 分").tag($0) } }
                TextEditor(text: $content).frame(minHeight: 120)
                Text("\(content.count) / 100 字").font(.cc.sm).foregroundStyle(content.count > 100 ? .red : .secondary)
                if review == nil { Toggle("同时分享到动态", isOn: $share) }
                if let error { Text(error) }
            }.disabled(saving).navigationTitle(review == nil ? "写短评" : "编辑短评")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) { Button("发布") { save() }.disabled(saving || content.count > 100) }
                }
                .onAppear { if let review { score = max(2, review.score); content = review.text } }
        }.piliInteractiveDismissDisabled(saving)
    }
    private func save() {
        guard !saving else { return }; saving = true; error = nil
        let action = PiliPGCReviewMutation.save(id: review?.id, score: score, text: content, share: share)
        Task {
            defer { saving = false }
            do { try await api.piliMutatePGCReview(mediaID: mediaID, action: action, identity: identity); onSave(); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}
