import Foundation

nonisolated struct PiliLivePlaybackPreferences: Codable, Equatable, Sendable {
    var quality = 400
    var cellularQuality = 400
    var cdnHost = ""
    static let qualities = [80, 150, 250, 400, 10000, 20000, 30000]
    func preferredQuality(cellular: Bool) -> Int {
        let value = cellular ? cellularQuality : quality
        return Self.qualities.contains(value) ? value : 400
    }
    func validate() throws {
        guard Self.qualities.contains(quality), Self.qualities.contains(cellularQuality) else { throw PiliOfflineError.message("请选择有效的直播画质") }
        guard cdnHost.isEmpty || Self.host(cdnHost) != nil else { throw PiliOfflineError.message("请输入 CDN 主机名，不包含协议、路径或端口") }
    }
    static func host(_ value: String) -> String? {
        guard !value.isEmpty, !value.contains(where: { $0.isWhitespace }), !value.contains("/"),
              let parts = URLComponents(string: "https://\(value)"), let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.port == nil, parts.query == nil, parts.fragment == nil else { return nil }
        return host
    }
    func candidates(_ original: [LiveStreamURLCandidate]) -> [LiveStreamURLCandidate] {
        guard let host = Self.host(cdnHost) else { return original }
        var seen = Set<URL>()
        let custom = original.compactMap { item -> LiveStreamURLCandidate? in
            guard ["https", "http"].contains(item.url.scheme ?? ""),
                  var parts = URLComponents(url: item.url, resolvingAgainstBaseURL: false) else { return nil }
            parts.host = host; parts.port = nil
            guard let url = parts.url, seen.insert(url).inserted else { return nil }
            return .init(url: url, protocolName: item.protocolName, formatName: item.formatName, codecName: item.codecName,
                         currentQN: item.currentQN, qualityTitle: item.qualityTitle, source: "customCDN")
        }
        return custom + original.filter { seen.insert($0.url).inserted }
    }
}
