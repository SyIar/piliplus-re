import SwiftUI
import WebKit

/// Official editors/appeal forms used by upstream. Each sheet has an isolated,
/// account-bound cookie store; changing accounts cannot submit an old form as a new user.
struct PiliAccountWebView: View {
    let api: BiliAPIClient
    let url: URL
    let title: String
    let purpose: BiliAccountPurpose
    private let version: Int
    @ObservedObject private var sessions: SessionStore
    init(api: BiliAPIClient, url: URL, title: String, purpose: BiliAccountPurpose = .main) {
        self.api = api; self.url = url; self.title = title; self.purpose = purpose
        version = api.requestSnapshot(purpose: purpose).playbackCredentialVersion
        _sessions = ObservedObject(wrappedValue: api.sessionStore)
    }
    var body: some View {
        Group {
            if api.requestSnapshot(purpose: purpose).playbackCredentialVersion != version {
                ContentUnavailableView("账号已切换", systemImage: "person.crop.circle.badge.exclamationmark", description: Text("请重新打开此页面"))
            } else {
                PiliIsolatedWebPage(url: url, cookies: api.requestSnapshot(purpose: purpose).cookieHeader)
            }
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

private struct PiliIsolatedWebPage: UIViewRepresentable {
    let url: URL
    let cookies: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        context.coordinator.loadTask = Task { @MainActor [weak view] in
            guard let view else { return }
            for cookie in PiliCookieImport.webCookies(from: cookies) {
                await configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
            }
            guard !Task.isCancelled else { return }
            view.load(URLRequest(url: url))
        }
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.loadTask?.cancel(); uiView.stopLoading(); uiView.navigationDelegate = nil; uiView.uiDelegate = nil
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loadTask: Task<Void, Never>?
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            let host = url.host?.lowercased() ?? ""
            if url.scheme == "https", host == "bilibili.com" || host.hasSuffix(".bilibili.com") {
                if action.targetFrame == nil { webView.load(action.request); decisionHandler(.cancel) }
                else { decisionHandler(.allow) }
            } else {
                decisionHandler(.cancel)
                if action.navigationType == .linkActivated, ["https", "http"].contains(url.scheme ?? "") {
                    UIApplication.shared.open(url)
                }
            }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    }
}
