import Foundation
import SwiftUI

/// Exercises production search UI with deterministic request responses.
struct PiliSearchHistoryFixture: View {
    @StateObject private var model: SearchViewModel
    @StateObject private var accessory = SearchBottomAccessoryStore()

    init(api: BiliAPIClient) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SearchHistoryFixtureProtocol.self]
        let fixtureAPI = BiliAPIClient(
            session: URLSession(configuration: configuration), sessionStore: api.sessionStore,
            libraryStore: api.libraryStore, homeRecommendDiagnosticsStore: api.homeRecommendDiagnosticsStore
        )
        let defaults = UserDefaults(suiteName: "SearchHistoryUIFixture")!
        defaults.set(["History demo"], forKey: "piliplus.search.history")
        _model = StateObject(wrappedValue: SearchViewModel(api: fixtureAPI, historyDefaults: defaults))
    }

    var body: some View {
        NavigationStack {
            SearchContentView(viewModel: model, showsHotSearches: false, accessoryStore: accessory)
                .navigationTitle("\u{641c}\u{7d22}")
                .navigationBarTitleDisplayMode(.inline)
                .nativeNavigationSearch(
                    text: $model.query, isPresented: $accessory.isSearchFocused,
                    isKeyboardVisible: $accessory.isKeyboardVisible, isEnabled: true,
                    prompt: "\u{641c}\u{7d22}", title: "\u{641c}\u{7d22}",
                    onSubmit: { Task { await model.search() } }
                )
                .onChange(of: model.query) { _, _ in model.queryChanged() }
        }
    }
}

nonisolated private final class SearchHistoryFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let keyword = query.first(where: { $0.name == "keyword" })?.value ?? ""
        let type = query.first(where: { $0.name == "search_type" })?.value ?? ""
        let payload: [String: Any]
        if url.path == "/x/web-interface/nav" {
            payload = ["wbi_img": ["img_url": "https://i.example.com/abc.png", "sub_url": "https://i.example.com/def.png"]]
        } else if type == "video" {
            payload = ["result": [["bvid": "BV1historyUI", "title": "\(keyword) video", "author": "Fixture author", "mid": 123, "duration": "1:00"]]]
        } else if type == "bili_user" {
            payload = ["result": [["mid": 123, "uname": "\(keyword) uploader"]]]
        } else {
            payload = ["result": []]
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: ["code": 0, "data": payload])
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
