import Foundation

nonisolated struct LiveCDNProbeProgress: Sendable {
    let bytes: Int
    let elapsed: Double
    let phase: String
    var bytesPerSecond: Double { Double(bytes) / max(0.001, elapsed) }
}

/// Bounded sampling of actual media, including the media segment behind an HLS manifest.
nonisolated final class LiveCDNProbeService: Sendable {
    static let byteLimit = 256 * 1024
    let session: URLSession
    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 7
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func probe(url: URL, headers: [String: String],
               progress: @Sendable (LiveCDNProbeProgress) async -> Void) async throws -> LiveCDNProbeProgress {
        var target = url
        var remainingBytes = Self.byteLimit
        for depth in 0..<3 {
            try Task.checkCancellation()
            var request = URLRequest(url: target, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
            // CDN requests never need account cookies, CSRF tokens or access keys.
            for (key, value) in headers where ["user-agent", "referer", "origin"].contains(key.lowercased()) {
                request.setValue(value, forHTTPHeaderField: key)
            }
            request.setValue("bytes=0-\(remainingBytes - 1)", forHTTPHeaderField: "Range")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            let started = ProcessInfo.processInfo.systemUptime
            await progress(.init(bytes: 0, elapsed: 0, phase: depth == 0 ? "连接线路" : "读取媒体片段"))
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse, [200, 206].contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let mime = (response.mimeType ?? "").lowercased()
            guard !mime.contains("html"), !mime.contains("json") else { throw URLError(.cannotDecodeContentData) }
            var data = Data()
            var lastUpdate = started
            for try await byte in bytes {
                data.append(byte)
                if data.count % 4096 == 0 {
                    try Task.checkCancellation()
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - lastUpdate >= 0.2 {
                        await progress(.init(bytes: data.count, elapsed: now - started, phase: "采样中"))
                        lastUpdate = now
                    }
                    if now - started >= 4 { break }
                }
                if data.count >= remainingBytes { break }
            }
            try Task.checkCancellation()
            guard !data.isEmpty else { throw URLError(.zeroByteResource) }
            remainingBytes -= data.count
            if let manifest = String(data: data, encoding: .utf8), manifest.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") {
                guard depth < 2, remainingBytes > 0, let next = Self.mediaURL(in: manifest, relativeTo: response.url ?? target) else { throw URLError(.cannotParseResponse) }
                target = next
                continue
            }
            guard !mime.hasPrefix("text/"), !target.path.lowercased().hasSuffix(".m3u8") else { throw URLError(.cannotDecodeContentData) }
            let result = LiveCDNProbeProgress(bytes: data.count, elapsed: ProcessInfo.processInfo.systemUptime - started, phase: "完成")
            await progress(result)
            return result
        }
        throw URLError(.cannotParseResponse)
    }

    static func mediaURL(in manifest: String, relativeTo base: URL) -> URL? {
        let lines = manifest.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let paths = lines.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        // Master playlists use the first rendition; media playlists sample a recent complete segment.
        let path = manifest.contains("#EXT-X-STREAM-INF") ? paths.first : paths.dropLast().last ?? paths.last
        guard let path, let url = URL(string: path, relativeTo: base)?.absoluteURL,
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil else { return nil }
        return url
    }
}
