import Foundation

nonisolated struct SponsorBlockSegment: Identifiable, Codable, Equatable, Sendable {
    var id: String { uuid }

    let uuid: String
    let category: String
    let actionType: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let videoDuration: TimeInterval?
    let votes: Int?

    var isSupportedAction: Bool { ["skip", "mute", "full", "poi"].contains(actionType) }

    var isSkippable: Bool {
        actionType.lowercased() == "skip" && endTime > startTime
    }

    var title: String {
        switch category.lowercased() {
        case "sponsor":
            return "赞助"
        case "selfpromo":
            return "推广"
        case "interaction":
            return "互动提醒"
        case "intro":
            return "开场"
        case "outro":
            return "片尾"
        case "preview":
            return "预览"
        case "padding":
            return "填充"
        case "filler":
            return "离题"
        case "music_offtopic":
            return "非音乐"
        default:
            return "空降片段"
        }
    }
}

nonisolated struct SponsorBlockSkipEvent: Equatable, Sendable {
    let segment: SponsorBlockSegment
    let fromTime: TimeInterval
    let skippedAt: Date
}

final class SponsorBlockService: @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "https://www.bsbsb.top")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchSkipSegments(bvid: String, cid: Int) async throws -> [SponsorBlockSegment] {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("/api/skipSegments"),
            resolvingAgainstBaseURL: false
        ) else {
            throw BiliAPIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "videoID", value: bvid),
            URLQueryItem(name: "cid", value: String(cid))
        ]
        guard let url = components.url else { throw BiliAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("", forHTTPHeaderField: "Cookie")
        request.setValue("cc.bili", forHTTPHeaderField: "Origin")
        request.setValue("cc.bili/1.0", forHTTPHeaderField: "X-Ext-Version")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return []
        }
        if httpResponse.statusCode == 404 {
            return []
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw BiliAPIError.api(code: httpResponse.statusCode, message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }

        return try await Self.decodeSegments(data)
    }

    @concurrent private static func decodeSegments(_ data: Data) async throws -> [SponsorBlockSegment] {
        guard data.count <= 4 * 1_024 * 1_024 else { throw PiliOfflineError.message("空降片段数据过大") }
        try Task.checkCancellation()
        let response = try JSONDecoder().decode([SponsorBlockSegmentResponse].self, from: data)
        guard response.count <= 1_000 else { throw PiliOfflineError.message("空降片段数据过大") }
        return response.compactMap(SponsorBlockSegment.init(response:)).filter(\.isSupportedAction)
            .sorted { $0.startTime < $1.startTime }
    }

    func vote(uuid: String, type: Int? = nil, category: String? = nil, userID: String) async throws {
        guard !uuid.isEmpty, !userID.isEmpty, (type != nil) != (category != nil),
              type == nil || [0, 1, 20].contains(type!),
              category == nil || PiliSponsorCategory(rawValue: category!) != nil else { throw BiliAPIError.missingPayload }
        var query = ["UUID": uuid, "userID": userID]
        if let type { query["type"] = String(type) }; if let category { query["category"] = category }
        _ = try await write("voteOnSponsorTime", query: query)
    }
    func submit(bvid: String, cid: Int, duration: Double, start: Double, end: Double, category: PiliSponsorCategory, action: String, userID: String) async throws {
        guard cid > 0, !bvid.isEmpty, !userID.isEmpty, duration.isFinite, duration > 0, start.isFinite, end.isFinite,
              start >= 0, end <= duration, (end > start || action == "poi" && end == start), category.actions.contains(action) else {
            throw PiliOfflineError.message("请检查片段时间、分类和动作")
        }
        let body: PiliJSON = .object(["videoID": .string(bvid), "cid": .string(String(cid)), "userID": .string(userID),
            "userAgent": .string("PiliPlusSwift/0.1"), "videoDuration": .decimal(duration),
            "segments": .array([.object(["segment": .array([.decimal(start), .decimal(end)]), "category": .string(category.rawValue), "actionType": .string(action)])])])
        _ = try await write("skipSegments", body: try JSONEncoder().encode(body))
    }
    private func write(_ path: String, query: [String: String] = [:], body: Data? = nil) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/\(path)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { .init(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw BiliAPIError.invalidURL }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("PiliPlusSwift", forHTTPHeaderField: "Origin"); request.setValue("PiliPlusSwift/0.1", forHTTPHeaderField: "X-Ext-Version")
        request.setValue("", forHTTPHeaderField: "Cookie")
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        // Deliberately one attempt: a lost response must not duplicate a public submission.
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BiliAPIError.emptyData }
        guard (200...299).contains(http.statusCode) else { throw BiliAPIError.api(code: http.statusCode, message: String(data: bytes.prefix(500), encoding: .utf8) ?? "空降社区请求失败") }
        return bytes
    }

    func reportViewed(uuid: String) async {
        guard let components = URLComponents(
            url: baseURL.appendingPathComponent("/api/viewedVideoSponsorTime"),
            resolvingAgainstBaseURL: false
        ) else {
            return
        }
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("", forHTTPHeaderField: "Cookie")
        request.setValue("cc.bili", forHTTPHeaderField: "Origin")
        request.setValue("cc.bili/1.0", forHTTPHeaderField: "X-Ext-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONEncoder().encode(["UUID": uuid])

        _ = try? await session.data(for: request)
    }
}

private nonisolated struct SponsorBlockSegmentResponse: Decodable {
    let category: String
    let actionType: String?
    let segment: [Double]
    let uuid: String
    let videoDuration: Double?
    let votes: Int?

    enum CodingKeys: String, CodingKey {
        case category
        case actionType
        case segment
        case uuid = "UUID"
        case videoDuration
        case votes
    }
}

private extension SponsorBlockSegment {
    nonisolated init?(response: SponsorBlockSegmentResponse) {
        guard response.segment.count >= 2 else { return nil }
        let startTime = response.segment[0]
        let endTime = response.segment[1]
        guard !response.uuid.isEmpty, startTime.isFinite, endTime.isFinite, startTime >= 0, endTime <= 31_536_000, (endTime > startTime || (response.actionType == "poi" && endTime == startTime)) else { return nil }

        self.init(
            uuid: response.uuid,
            category: response.category,
            actionType: response.actionType ?? "skip",
            startTime: startTime,
            endTime: endTime,
            videoDuration: response.videoDuration,
            votes: response.votes
        )
    }
}
