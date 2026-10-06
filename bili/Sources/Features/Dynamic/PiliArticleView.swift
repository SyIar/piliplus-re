import SwiftUI
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
                    Text(document.title).font(.title2.bold()).textSelection(.enabled)
                    if let author = document.author { NavigationLink(value: author) { Text(author.name).font(.subheadline) } }
                    if !document.blockedText.isEmpty { Text(document.blockedText).foregroundStyle(.secondary) }
                    ForEach(Array(document.paragraphs.enumerated()), id: \.offset) { _, paragraph in PiliArticleParagraph(value: paragraph, api: api) }
                    if !document.html.isEmpty { PiliArticleHTML(html: document.html) }
                    ForEach(Array(document.operations.enumerated()), id: \.offset) { _, op in PiliNoteOperationView(operation: op) }
                    HStack {
                        if !document.dynamicID.isEmpty { Button(liked ? "取消点赞" : "点赞") { action(favorite: false) } }
                        if document.commentType == 12 { Button(favorited ? "取消收藏" : "收藏") { action(favorite: true) } }
                        if document.commentID > 0 { Button("评论") { comments = try? document.commentTarget() } }
                    }.buttonStyle(.bordered).disabled(busy)
                    PiliShareMenu(url: document.route.url, title: document.title) { Label("分享", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                    Link("查看原文", destination: document.route.url).environment(\.openURL, OpenURLAction { _ in .systemAction })
                } else if error == nil { ProgressView("加载正文") }
                if let error { Text(error).foregroundStyle(.red); Button("重新加载") { Task { await load() } } }
            }.padding(20)
        }.navigationTitle("图文").navigationBarTitleDisplayMode(.inline)
            .task(id: route) { identity = .init(api.requestSnapshot(purpose: .main)); await load() }
            .sheet(item: $comments) { DynamicCommentsSheet(item: $0, api: api) }
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
                    try await api.piliContentWrite(favorited ? "/x/article/favorites/del" : "/x/article/favorites/add", fields: ["id": String(document.commentID)], identity: identity)
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
            Text(Self.richText((kind == 8 ? value["heading"] : value["text"])["nodes"].piliArray))
                .font(kind == 8 ? .title3.bold() : .body).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: value["align"].piliInt == 1 ? .center : .leading)
                .padding(.leading, kind == 4 ? 12 : 0).overlay(alignment: .leading) { if kind == 4 { Rectangle().fill(.secondary.opacity(0.4)).frame(width: 3) } }
        case 2:
            ForEach(value["pic"]["pics"].piliArray, id: \.self) { pic in image(pic["url"].piliString) }
        case 3:
            if !value["line"]["pic"]["url"].piliString.isEmpty { image(value["line"]["pic"]["url"].piliString) } else { Divider() }
        case 5:
            ForEach(Array(value["list"]["items"].piliArray.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top) { Text(value["list"]["style"].piliInt == 1 ? "\(index + 1)." : "•"); Text(Self.richText(item["nodes"].piliArray.isEmpty ? item["text"]["nodes"].piliArray : item["nodes"].piliArray)).textSelection(.enabled) }
            }
        case 6:
            let card = value["link_card"]["card"]
            let cards = card.piliObject.isEmpty ? value["link_card"]["cards"].piliArray : [card]
            ForEach(cards, id: \.self) { card in
                if card["vote"]["vote_id"].piliInt > 0 {
                    NavigationLink { PiliVoteView(api: api, id: card["vote"]["vote_id"].piliInt) } label: { Label(card["vote"]["desc"].piliString, systemImage: "chart.bar") }
                } else { cardView(card) }
            }
        case 7:
            ScrollView(.horizontal) { Text(value["code"]["content"].piliString).font(.system(.body, design: .monospaced)).textSelection(.enabled) }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        default:
            if !value.dynamicDisplayText.orEmpty.isEmpty { Text(value.dynamicDisplayText.orEmpty).textSelection(.enabled) }
        }
    }
    private func image(_ raw: String) -> some View {
        VStack {
            ZoomyRemoteImage(url: URL(string: raw.normalizedBiliURL()), targetPixelSize: 1600,
                cornerRadius: 8, contentMode: .fit) { ProgressView().frame(height: 120) }
        }
    }
    @ViewBuilder private func cardView(_ card: DynamicJSONValue) -> some View {
        let content = ["ugc", "opus", "live", "common", "music"].map { card[$0] }.first { !$0.piliObject.isEmpty } ?? card
        if let url = URL(string: content["jump_url"].piliString.normalizedBiliURL()), !content["jump_url"].piliString.isEmpty {
            Link(destination: url) {
                VStack(alignment: .leading) { Text(content["title"].piliString).font(.headline); Text(content["desc"].piliString).font(.caption) }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
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

struct PiliArticleHTML: UIViewRepresentable {
    let html: String
    @Environment(\.openURL) private var openURL
    func makeCoordinator() -> Coordinator { Coordinator(openURL: openURL) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent(); config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config); view.isOpaque = false; view.backgroundColor = .clear; view.navigationDelegate = context.coordinator
        view.scrollView.isScrollEnabled = true
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.html != html else { return }; context.coordinator.html = html
        view.loadHTMLString("<meta name='viewport' content='width=device-width,initial-scale=1'><style>:root{color-scheme:light dark}body{font:17px -apple-system;line-height:1.7;margin:0;background:transparent}img,video{max-width:100%;height:auto}pre{white-space:pre-wrap}a{color:#3264f0}</style>" + html, baseURL: URL(string: "https://www.bilibili.com/"))
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: WKWebView, context: Context) -> CGSize? { CGSize(width: proposal.width ?? 320, height: max(500, proposal.height ?? 620)) }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var html = ""
        let openURL: OpenURLAction
        init(openURL: OpenURLAction) { self.openURL = openURL }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url { openURL(url); decisionHandler(.cancel) }
            else { decisionHandler(action.navigationType == .other ? .allow : .cancel) }
        }
    }
}

private extension Optional where Wrapped == String { var orEmpty: String { self ?? "" } }
