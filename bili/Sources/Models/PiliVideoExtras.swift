import Foundation

nonisolated struct PiliVideoChapter: Identifiable, Hashable, Sendable {
    let start: Double
    let end: Double
    let title: String
    let image: String
    var id: String { "\(start)|\(end)|\(title)" }
    init?(_ value: DynamicJSONValue) {
        start = Double(value["from"].piliString) ?? 0; end = Double(value["to"].piliString) ?? 0
        title = value["content"].piliString; image = value["img_url"].piliString.normalizedBiliURL()
        guard value["type"].piliInt == 2, start.isFinite, end.isFinite, start >= 0, end > start, !title.isEmpty else { return nil }
    }
}

nonisolated struct PiliPGCClip: Decodable, Hashable, Identifiable, Sendable {
    let start: Double
    let end: Double
    let clipType: String
    init(start: Double, end: Double, clipType: String) { self.start = start; self.end = end; self.clipType = clipType }
    init(from decoder: Decoder) throws {
        let raw = try DynamicJSONValue(from: decoder)
        start = Double(raw["start"].piliString) ?? -1
        end = Double(raw["end"].piliString) ?? -1
        clipType = raw["clipType"].piliString
    }
    var id: String { "\(clipType)|\(start)|\(end)" }
    var title: String { clipType == "CLIP_TYPE_OP" ? "片头" : "片尾" }
    var isValid: Bool { ["CLIP_TYPE_OP", "CLIP_TYPE_ED"].contains(clipType) && start.isFinite && end.isFinite && start >= 0 && end > start }
}

nonisolated struct PiliVideoStaff: Identifiable, Sendable {
    let owner: VideoOwner
    let role: String
    var id: Int { owner.mid }
}
nonisolated struct PiliVideoTag: Identifiable, Sendable { let id: Int; let title: String }

nonisolated struct PiliVideoEnergy: Sendable {
    let step: Double
    let values: [Double]
    init?(_ json: DynamicJSONValue) {
        let embedded = json["modules"].piliArray.first?["params"]["data"] ?? .null
        let data: DynamicJSONValue
        if case .null = embedded { data = json } else { data = embedded }
        step = Double(data["step_sec"].piliString) ?? 0
        let samples = data["events"]["default"].piliArray
        guard step.isFinite, step > 0, !samples.isEmpty, samples.count <= 100_000 else { return nil }
        let raw = samples.map { max(0, Double($0.piliString) ?? 0) }.map { $0.isFinite ? $0 : 0 }
        // Bucket once when loading, never rebuild a giant path on each clock tick.
        let stride = max(1, Int(ceil(Double(raw.count) / 400)))
        var buckets: [Double] = []
        for start in Swift.stride(from: 0, to: raw.count, by: stride) {
            buckets.append(raw[start..<min(raw.count, start + stride)].max() ?? 0)
        }
        let peak = buckets.max() ?? 0
        values = buckets.map { peak > 0 ? $0 / peak : 0 }
    }
}

extension BiliAPIClient {
    func piliVideoChapters(bvid: String, cid: Int, seasonID: Int? = nil, episodeID: Int? = nil) async throws -> [PiliVideoChapter] {
        var query = ["bvid": bvid, "cid": String(cid)]
        if let seasonID { query["season_id"] = String(seasonID) }
        if let episodeID { query["ep_id"] = String(episodeID) }
        let data = try await piliContentRead("/x/player/wbi/v2", query: query, signed: true, purpose: .playback)
        return data["view_points"].piliArray.compactMap(PiliVideoChapter.init).sorted { $0.start < $1.start }
    }
    func piliVideoEnergy(bvid: String, aid: Int, cid: Int) async throws -> PiliVideoEnergy? {
        let request = try await makeRequest(base: URL(string: "https://bvc.bilivideo.com")!, path: "/pbp/data",
            query: ["bvid": bvid, "aid": String(aid), "cid": String(cid), "r": "loader"],
            referer: "https://www.bilibili.com/video/\(bvid)", cookieHeader: "")
        let (bytes, _) = try await data(for: request, priority: URLSessionTask.lowPriority)
        guard bytes.count <= 4 * 1024 * 1024 else { throw BiliAPIError.missingPayload }
        let json: DynamicJSONValue = try await Self.decode(bytes, priority: URLSessionTask.lowPriority)
        return PiliVideoEnergy(json)
    }
    func piliVideoCredits(bvid: String) async throws -> [PiliVideoStaff] {
        let data = try await piliContentRead("/x/web-interface/view", query: ["bvid": bvid])
        var seen = Set<Int>()
        return data["staff"].piliArray.compactMap { item in
            let id = item["mid"].piliInt
            guard id > 0, seen.insert(id).inserted else { return nil }
            return .init(owner: .init(mid: id, name: item["name"].piliString, face: item["face"].piliString), role: item["title"].piliString)
        }
    }
    func piliVideoTags(bvid: String) async throws -> [PiliVideoTag] {
        let data = try await piliContentRead("/x/tag/archive/tags", query: ["bvid": bvid])
        var seen = Set<Int>()
        return data.piliArray.compactMap { item in
            let id = item["tag_id"].piliInt, name = item["tag_name"].piliString
            return id > 0 && !name.isEmpty && seen.insert(id).inserted ? .init(id: id, title: name) : nil
        }
    }
}
