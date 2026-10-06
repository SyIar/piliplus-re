import SwiftUI
import ChunUI

nonisolated enum PiliCookieImport {
    static func values(from text: String) -> [String: String] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let header = text.lowercased().hasPrefix("cookie:") ? String(text.dropFirst(7)) : text
        var values = [String: String]()
        for pair in header.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !value.isEmpty,
                  !name.contains(where: { $0.isWhitespace || $0.isNewline }),
                  !value.contains(where: { $0.isNewline || $0.asciiValue == 0 }) else { continue }
            values[name] = value
        }
        return values
    }
    static func webCookies(from header: String) -> [HTTPCookie] {
        values(from: header).compactMap { name, value in
            // App tokens do not belong in a webpage's cookie jar.
            guard name != "access_key" else { return nil }
            return HTTPCookie(properties: [.name: name, .value: value, .domain: ".bilibili.com", .path: "/", .secure: "TRUE"])
        }
    }
}

struct PiliCookieLoginView: View {
    let api: BiliAPIClient
    let onLogin: ([HTTPCookie]) -> Void
    @State private var input = ""
    @State private var busy = false
    @State private var error: String?
    @PiliDismiss private var dismiss
    var body: some View {
        PiliForm {
            Section("粘贴 Cookie") {
                TextEditor(text: $input).piliFont(.base).monospaced().frame(minHeight: 180)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                Text("至少包含 SESSDATA；验证账号成功后保存到系统钥匙串。").piliFont(.sm).foregroundStyle(.secondary)
            }
            Button("验证并登录") { Task { await login() } }.disabled(busy || input.isEmpty)
            if busy { ProgressView("验证账号") }
            if let error { Text(error).foregroundStyle(Color.cc.destructive) }
        }.navigationTitle("Cookie 登录").navigationBarTitleDisplayMode(.inline)
    }
    private func login() async {
        guard !busy else { return }
        busy = true; error = nil
        let version = api.requestSnapshot(purpose: .main).playbackCredentialVersion
        defer { busy = false }
        do {
            var values = PiliCookieImport.values(from: input)
            guard values["SESSDATA"]?.isEmpty == false else { throw PiliOfflineError.message("Cookie 中缺少 SESSDATA") }
            let header = values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            let response: BiliResponse<DynamicJSONValue> = try await api.get(base: api.baseURL, path: "/x/web-interface/nav", query: [:],
                cookieHeader: header, cachePolicy: .reloadIgnoringLocalCacheData)
            guard response.code == 0, let payload = response.payload, payload["isLogin"] == .bool(true), payload["mid"].piliInt > 0 else {
                throw PiliOfflineError.message("Cookie 已失效，请重新获取")
            }
            guard api.requestSnapshot(purpose: .main).playbackCredentialVersion == version else { throw PiliOfflineError.message("账号已变更，请重试") }
            values["DedeUserID"] = payload["mid"].piliString
            let verified = values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            input = ""
            onLogin(PiliCookieImport.webCookies(from: verified))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
