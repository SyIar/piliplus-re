import Foundation
import PiliPlaybackCore

nonisolated struct PiliWebDAVClient: Sendable {
    let baseURL: URL
    private let rootURL: URL
    let username: String
    let password: String
    private let session: URLSession
    init(address: String, username: String, password: String, session: URLSession? = nil) throws {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw PiliOfflineError.message("请输入完整的 WebDAV 目录地址，账号密码请填写在单独字段")
        }
        rootURL = URL(string: url.absoluteString.hasSuffix("/") ? url.absoluteString : url.absoluteString + "/")!
        baseURL = rootURL.appendingPathComponent("PiliPlusSwift", isDirectory: true)
        self.username = username; self.password = password
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil; config.urlCredentialStorage = nil
            config.timeoutIntervalForRequest = 30
            self.session = URLSession(configuration: config, delegate: PiliWebDAVNoRedirectDelegate(), delegateQueue: nil)
        }
    }
    func testConnection() async throws {
        let xml = Data(#"<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>"#.utf8)
        _ = try await send("PROPFIND", url: rootURL, body: xml,
                           headers: ["Depth": "0", "Content-Type": "application/xml; charset=utf-8"], accepted: [200, 207])
    }
    func backup(_ archive: SettingsArchive) async throws {
        _ = try await send("MKCOL", url: baseURL, accepted: [201, 405])
        let data = try JSONEncoder().encode(archive)
        _ = try await send("PUT", url: baseURL.appendingPathComponent("settings.json"), body: data,
                           headers: ["Content-Type": "application/json"], accepted: [200, 201, 204])
    }
    func restore() async throws -> SettingsArchive {
        let data = try await send("GET", url: baseURL.appendingPathComponent("settings.json"), accepted: [200])
        return try SettingsArchive.decode(data)
    }
    private func send(_ method: String, url: URL, body: Data? = nil, headers: [String: String] = [:], accepted: Set<Int>) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body; request.httpShouldHandleCookies = false
        request.setValue("Basic " + Data("\(username):\(password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, accepted.contains(response.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 { throw PiliOfflineError.message("WebDAV 拒绝访问，请检查账号、密码和目录权限") }
            if (300...399).contains(status) { throw PiliOfflineError.message("WebDAV 地址发生重定向，请填写服务器的最终目录地址") }
            if status == 404 { throw PiliOfflineError.message("没有找到设置备份，请先备份或检查目录") }
            throw PiliOfflineError.message("WebDAV 返回 HTTP \(status)")
        }
        guard data.count <= 10 * 1024 * 1024 else { throw SettingsArchive.ArchiveError.tooLarge }
        return data
    }
}

nonisolated private final class PiliWebDAVNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward a user's Basic credentials to a redirected origin.
        completionHandler(nil)
    }
}
