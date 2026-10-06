import SwiftUI
import ChunUI
import WebKit

struct PiliArticleView: View {
    let api: BiliAPIClient
    let route: PiliArticleRoute
    @Environment(\.openURL) private var openURL
    @State private var document: PiliArticleDocument?
    @State private var error: String?
    @State private var comments: DynamicFeedItem?
    @State private var liked = false
    @State private var favorited = false
    @State private var busy = false
    @State private var identity: PiliAccountIdentity?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let document {
                    Text(document.title).font(.cc.lgBold.bold()).textSelection(.enabled)
                    if let author = document.author { NavigationLink(value: author) { Text(author.name).font(.cc.base) } }
                    if !document.blockedText.isEmpty { Text(document.blockedText).foregroundStyle(.secondary) }
                    ForEach(Array(document.paragraphs.enumerated()), id: \.offset) { _, paragraph in PiliArticleParagraph(value: paragraph, api: api) }
                    if !document.html.isEmpty { PiliArticleHTML(html: document.html) }
                    ForEach(Array(document.operations.enumerated()), id: \.offset) { _, op in PiliNoteOperationView(operation: op) }
                    HStack {
                        if !document.dynamicID.isEmpty { Button(liked ? "取消点赞" : "点赞") { action(favorite: false) } }
                        if document.commentType == 12 || document.route.kind == .opus { Button(favorited ? "取消收藏" : "收藏") { action(favorite: true) } }
                        if document.commentID > 0 { Button("评论") { comments = try? document.commentTarget() } }
                    }.buttonStyle(.glass).disabled(busy)
                    PiliShareMenu(url: document.route.url, title: document.title) { PiliLabel("分享", systemImage: "square.and.arrow.up") }.buttonStyle(.glass)
                    Link("查看原文", destination: document.route.url).environment(\.openURL, OpenURLAction { _ in .systemAction })
                } else if error == nil { ProgressView("加载正文") }
                if let error { Text(error).foregroundStyle(Color.cc.destructive); Button("重新加载") { Task { await load() } } }
            }.padding(20)
        }.navigationTitle("图文").navigationBarTitleDisplayMode(.inline)
            .task(id: route) { identity = .init(api.requestSnapshot(purpose: .main)); await load() }
            .piliSheet(item: $comments) { DynamicCommentsSheet(item: $0, api: api) }
    }
    private func load() async {
        do { let value = try await api.piliArticle(route); document = value; liked = value.liked; favorited = value.favorited; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func action(favorite: Bool) {
        guard let document, let identity, !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do {
                if favorite {
                    if document.route.kind == .opus {
                        try await api.piliOpusFavorite(id: document.route.id, add: !favorited, identity: identity)
                    } else {
                        try await api.piliContentWrite(favorited ? "/x/article/favorites/del" : "/x/article/favorites/add", fields: ["id": String(document.commentID)], identity: identity)
                    }
                    favorited.toggle()
                } else {
                    try await api.piliContentWrite("/x/dynamic/feed/operate/thumb", body: .object(["dyn_id_str": .string(document.dynamicID), "up": .int(liked ? 2 : 1)]), identity: identity)
                    liked.toggle()
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct PiliArticleParagraph: View {
    let value: DynamicJSONValue
    let api: BiliAPIClient
    var body: some View {
        let kind = value["para_type"].piliInt
        switch kind {
        case 1, 4, 8:
            PiliArticleRichText(nodes: (kind == 8 ? value["heading"] : value["text"])["nodes"].piliArray)
                .font(kind == 8 ? .title3.bold() : .body).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: value["align"].piliInt == 1 ? .center : .leading)
                .padding(.leading, kind == 4 ? 12 : 0).overlay(alignment: .leading) { if kind == 4 { Rectangle().fill(.secondary.opacity(0.4)).frame(width: 3) } }
        case 2:
            ForEach(value["pic"]["pics"].piliArray, id: \.self) { pic in image(pic["url"].piliString, liveVideo: pic["live_url"].piliString) }
        case 3:
            if !value["line"]["pic"]["url"].piliString.isEmpty { image(value["line"]["pic"]["url"].piliString) } else { Divider() }
        case 5:
            ForEach(Array(value["list"]["items"].piliArray.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top) { Text(value["list"]["style"].piliInt == 1 ? "\(index + 1)." : "•"); PiliArticleRichText(nodes: item["nodes"].piliArray.isEmpty ? item["text"]["nodes"].piliArray : item["nodes"].piliArray).textSelection(.enabled) }
            }
        case 6:
            let card = value["link_card"]["card"]
            let cards = card.piliObject.isEmpty ? value["link_card"]["cards"].piliArray : [card]
            ForEach(cards, id: \.self) { card in
                if card["vote"]["vote_id"].piliInt > 0 {
                    NavigationLink { PiliVoteView(api: api, id: card["vote"]["vote_id"].piliInt) } label: { PiliLabel(card["vote"]["desc"].piliString, systemImage: "chart.bar") }
                } else { cardView(card) }
            }
        case 7:
            ScrollView(.horizontal) { Text(value["code"]["content"].piliString).font(.cc.base.monospaced()).textSelection(.enabled) }.padding().piliGlassCard(radius: 12)
        default:
            if !value.dynamicDisplayText.orEmpty.isEmpty { Text(value.dynamicDisplayText.orEmpty).textSelection(.enabled) }
        }
    }
    private func image(_ raw: String, liveVideo: String = "") -> some View {
        let url = URL(string: raw.normalizedBiliURL())
        let item = ZoomyImagePreviewItem(id: raw, viewerURL: url, mediaBadgeText: liveVideo.isEmpty ? nil : "LIVE",
            liveVideoURL: liveVideo.isEmpty ? nil : URL(string: liveVideo.normalizedBiliURL()))
        return VStack {
            ZoomyRemoteImage(url: url, viewerItems: [item], viewerItemID: raw, targetPixelSize: 1600,
                cornerRadius: 8, contentMode: .fit) { ProgressView().frame(height: 120) }
        }
    }
    @ViewBuilder private func cardView(_ card: DynamicJSONValue) -> some View {
        let content = ["ugc", "opus", "live", "common", "music"].map { card[$0] }.first { !$0.piliObject.isEmpty } ?? card
        if let url = URL(string: content["jump_url"].piliString.normalizedBiliURL()), !content["jump_url"].piliString.isEmpty {
            Link(destination: url) {
                VStack(alignment: .leading) { Text(content["title"].piliString).font(.cc.baseBold); Text(content["desc"].piliString).font(.cc.sm) }.frame(maxWidth: .infinity, alignment: .leading).padding().piliGlassCard(radius: 12)
            }
        } else if !content["title"].piliString.isEmpty { Text(content["title"].piliString) }
    }
    static func richText(_ nodes: [DynamicJSONValue]) -> AttributedString {
        nodes.reduce(into: AttributedString()) { result, node in
            let word = node["word"], rich = node["rich"]
            var text = word["words"].piliString
            if text.isEmpty { text = rich["text"].piliString.isEmpty ? rich["orig_text"].piliString : rich["text"].piliString }
            if text.isEmpty { text = node["formula"]["latex_content"].piliString }
            var fragment = AttributedString(text)
            let style = word.piliObject.isEmpty ? rich["style"] : word["style"]
            var intent = InlinePresentationIntent()
            if style["bold"].piliInt == 1 { intent.insert(.stronglyEmphasized) }
            if style["italic"].piliInt == 1 { intent.insert(.emphasized) }
            fragment.inlinePresentationIntent = intent
            if style["strikethrough"].piliInt == 1 { fragment.strikethroughStyle = .single }
            let jump = rich["jump_url"].piliString.normalizedBiliURL()
            if let url = URL(string: jump), ["https", "http"].contains(url.scheme ?? "") { fragment.link = url }
            result.append(fragment)
        }
    }
}

struct PiliArticleHTML: View {
    let html: String
    @State private var height: CGFloat = 80
    var body: some View { PiliArticleWebContent(html: html, height: $height).frame(height: height) }
}

private struct PiliArticleWebContent: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    @Environment(\.openURL) private var openURL
    func makeCoordinator() -> Coordinator { Coordinator(openURL: openURL, height: $height) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false; view.backgroundColor = .clear; view.navigationDelegate = context.coordinator
        view.scrollView.isScrollEnabled = false
        context.coordinator.observation = view.scrollView.observe(\.contentSize, options: [.new]) { [weak coordinator = context.coordinator] _, change in
            guard let size = change.newValue, size.height > 0, size.height.isFinite else { return }
            Task { @MainActor [weak coordinator] in coordinator?.resize(size.height) }
        }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.height = $height
        view.scrollView.isScrollEnabled = context.coordinator.contentHeight > 20_000
        guard context.coordinator.html != html else { return }; context.coordinator.html = html
        view.loadHTMLString("<meta name='viewport' content='width=device-width,initial-scale=1'><style>:root{color-scheme:light dark}body{font:17px -apple-system;line-height:1.7;margin:0;background:transparent;overflow-wrap:anywhere}img,video{max-width:100%;height:auto}img.emote{height:1.5em;vertical-align:middle}img.formula{vertical-align:middle;max-height:12em}pre{white-space:pre-wrap}a{color:#3264f0}table{max-width:100%;border-collapse:collapse}td,th{border:1px solid #8888;padding:6px}</style>" + html, baseURL: URL(string: "https://www.bilibili.com/"))
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.observation?.invalidate(); coordinator.observation = nil; view.stopLoading(); view.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var html = ""
        var observation: NSKeyValueObservation?
        var contentHeight: CGFloat = 80
        var height: Binding<CGFloat>
        let openURL: OpenURLAction
        init(openURL: OpenURLAction, height: Binding<CGFloat>) { self.openURL = openURL; self.height = height }
        func resize(_ value: CGFloat) {
            contentHeight = value
            // Extremely long legacy articles retain their own scroll surface.
            let next: CGFloat = value > 20_000 ? 900 : max(36, ceil(value))
            if abs(height.wrappedValue - next) > 1 { height.wrappedValue = next }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url { openURL(url); decisionHandler(.cancel) }
            else { decisionHandler(action.navigationType == .other ? .allow : .cancel) }
        }
    }
}

struct PiliArticleRichText: View {
    let nodes: [DynamicJSONValue]
    var body: some View {
        if nodes.contains(where: { !$0["formula"]["latex_content"].piliString.isEmpty || !$0["rich"]["emoji"].piliObject.isEmpty }) {
            PiliArticleHTML(html: Self.html(nodes))
        } else { Text(PiliArticleParagraph.richText(nodes)) }
    }
    nonisolated static func html(_ nodes: [DynamicJSONValue]) -> String {
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
        }
        return nodes.map { node in
            let formula = node["formula"]["latex_content"].piliString
            if !formula.isEmpty {
                var url = URLComponents(string: "https://api.bilibili.com/x/web-frontend/mathjax/tex")!
                url.queryItems = [URLQueryItem(name: "formula", value: formula)]
                return "<img class='formula' alt='\(escape(formula))' src='\(escape(url.url!.absoluteString))'>"
            }
            let rich = node["rich"], word = node["word"]
            let label = word["words"].piliString.isEmpty ? (rich["text"].piliString.isEmpty ? rich["orig_text"].piliString : rich["text"].piliString) : word["words"].piliString
            var content = escape(label).replacingOccurrences(of: "\n", with: "<br>")
            let emoji = rich["emoji"]["url"].piliString.normalizedBiliURL()
            if let url = URL(string: emoji), ["https", "http"].contains(url.scheme ?? "") {
                content = "<img class='emote' src='\(escape(emoji))' alt='\(escape(label))'>"
            }
            let style = word.piliObject.isEmpty ? rich["style"] : word["style"]
            if style["bold"].piliInt == 1 { content = "<b>" + content + "</b>" }
            if style["italic"].piliInt == 1 { content = "<i>" + content + "</i>" }
            if style["strikethrough"].piliInt == 1 { content = "<s>" + content + "</s>" }
            var jump = rich["jump_url"].piliString.normalizedBiliURL()
            if rich["type"].piliString == "RICH_TEXT_NODE_TYPE_AT", rich["rid"].piliInt > 0 { jump = "https://space.bilibili.com/\(rich["rid"].piliInt)" }
            if let url = URL(string: jump), ["https", "http"].contains(url.scheme ?? "") { content = "<a href='\(escape(jump))'>" + content + "</a>" }
            return content
        }.joined()
    }
}

private extension Optional where Wrapped == String { var orEmpty: String { self ?? "" } }
