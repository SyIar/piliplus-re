import Foundation
import SwiftUI

struct PiliSuperChatFixture: View {
    let api: BiliAPIClient
    @StateObject private var store = PiliSuperChatStore()
    var body: some View {
        PiliSuperChatHistoryView(store: store, api: api, roomID: 99)
            .onAppear {
                store.mode = 1
                let now = Int(Date().timeIntervalSince1970)
                let current = PiliSuperChat(dictionary: ["id": 701, "uid": 1, "price": 50, "message": "清晰的画面，也要清晰地呈现每一条留言。",
                    "start_time": now - 10, "end_time": now + 300, "user_info": ["uname": "观众"], "background_bottom_color": "#3264F0"])
                let expired = PiliSuperChat(dictionary: ["id": 702, "uid": 2, "price": 30, "message": "这条留言已经结束展示，仍可在历史中查看。",
                    "start_time": now - 300, "end_time": now - 1, "user_info": ["uname": "另一位观众"]])
                store.ingest([current, expired].compactMap { $0 })
            }
    }
}

struct PiliContentExportFixture: View {
    var body: some View {
        PiliContentImageExportView(document: .init(title: "评论", author: "模拟器预览",
            text: String(repeating: "完整内容保存测试：长评论会分页导出，不受当前屏幕高度限制。\n", count: 80), pictures: [], source: "https://www.bilibili.com/video/BVfixture"))
    }
}

struct PiliDynamicComposerFixture: View {
    @State private var api: BiliAPIClient?
    @State private var published = false
    @State private var error: String?
    var body: some View {
        Group {
            if published { Text("模拟发布成功").accessibilityIdentifier("fixture.dynamic.published") }
            else if let api {
                let draft = { var value = PiliDynamicDraft(); value.tokens = [.init(text: "模拟器动态正文")]; return value }()
                PiliDynamicComposer(api: api, initial: draft) { published = true }
            } else if let error { Text(error) }
            else { ProgressView() }
        }.task {
            guard api == nil else { return }
            do {
                let name = "PiliDynamicComposerFixture"
                let store = SessionStore(keychain: KeychainStore(service: name))
                try store.saveLoginCookies(["SESSDATA": "fixture-only", "DedeUserID": "900000001", "bili_jct": "fixture-csrf"], credentialKind: .web)
                let defaults = UserDefaults(suiteName: name)!
                defaults.removePersistentDomain(forName: name)
                let config = URLSessionConfiguration.ephemeral
                config.protocolClasses = [PiliContentFixtureProtocol.self]
                config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCache = nil
                try await PiliDraftStorage.shared.remove(key: "900000001.dynamic.new")
                api = BiliAPIClient(session: URLSession(configuration: config), sessionStore: store,
                    libraryStore: LibraryStore(userDefaults: defaults), homeRecommendDiagnosticsStore: .shared)
            } catch { self.error = error.localizedDescription }
        }
    }
}

/// This session intercepts every request. The fixture cannot publish to Bilibili.
nonisolated private final class PiliContentFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body: String
        switch request.url?.path {
        case "/x/emote/user/panel/web": body = #"{"code":0,"data":{"packages":[]}}"#
        case "/x/polymer/web-dynamic/v1/mention/search":
            body = #"{"code":0,"data":{"groups":[{"items":[{"uid":101,"name":"测试用户"}]}]}}"#
        case "/x/dynamic/feed/create/dyn":
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while data.count < 1_048_576 {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
                }
            }
            let json = (try? JSONDecoder().decode(DynamicJSONValue.self, from: data)) ?? .null
            let content = json["dyn_req"]["content"]
            let valid = content["title"].piliString == "Simulator draft"
                && content["contents"].piliArray.contains { $0["type"].piliInt == 2 && $0["biz_id"].piliString == "101" }
            body = valid ? #"{"code":0,"data":{"dyn_id_str":"999001"}}"# : #"{"code":-400,"message":"fixture payload mismatch"}"#
        default: body = #"{"code":-404,"message":"fixture has no matching route"}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
