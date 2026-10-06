import Foundation

nonisolated struct PiliFeedFeedbackReason: Codable, Hashable, Identifiable, Sendable {
    let value: Int
    let name: String
    let kind: String
    var id: String { "\(kind):\(value)" }
    var parameter: String { kind == "feedback" ? "feedback_id" : "reason_id" }
}

nonisolated struct PiliRecommendationMetadata: Codable, Hashable, Sendable {
    let targetID: String
    let targetKind: String
    let reasons: [PiliFeedFeedbackReason]
    let followed: Bool
    let zone: String

    static func reasons(_ value: DynamicJSONValue?) -> [PiliFeedFeedbackReason] {
        var seen = Set<String>()
        return (value?.piliArray ?? []).flatMap { group -> [PiliFeedFeedbackReason] in
            let kind = group["type"].piliString
            guard ["dislike", "feedback"].contains(kind) else { return [] }
            return group["reasons"].piliArray.compactMap { reason in
                let id = reason["id"].piliInt, name = reason["name"].piliString
                guard id > 0, !name.isEmpty, seen.insert("\(kind):\(id)").inserted else { return nil }
                return .init(value: id, name: name, kind: kind)
            }
        }
    }
}

nonisolated struct PiliAdvancedRecommendFilter: Codable, Equatable, Sendable {
    var titlePattern = ""
    var zonePattern = ""
    var exemptsFollowed = false
    func validate() throws {
        for pattern in [titlePattern, zonePattern] where !pattern.isEmpty {
            guard pattern.count <= 256 else { throw PiliOfflineError.message("正则表达式最多 256 个字符") }
            _ = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
    }
}
