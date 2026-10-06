import Foundation

nonisolated struct PiliCommentKeywordRules: Sendable {
    let words: [String]
    init(_ raw: String) {
        var seen = Set<String>()
        words = raw.split(whereSeparator: \.isNewline).prefix(200).compactMap {
            let value = String($0.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
            return !value.isEmpty && seen.insert(value.lowercased()).inserted ? value : nil
        }
    }
    func filter(_ comments: [Comment], blocksGoods: Bool, depth: Int = 0) -> [Comment] {
        guard !words.isEmpty || blocksGoods else { return comments }
        return comments.compactMap { comment in
            guard !blocksGoods || !comment.containsGoodsPromotion else { return nil }
            let message = comment.content?.message ?? ""
            guard !words.contains(where: { message.localizedCaseInsensitiveContains($0) }) else { return nil }
            if let replies = comment.replies, !replies.isEmpty {
                return comment.replacingPreviewReplies(depth < 32 ? filter(replies, blocksGoods: blocksGoods, depth: depth + 1) : [])
            }
            return comment
        }
    }
}

@MainActor
enum PiliCommentKeywordFilter {
    static let key = "piliplus.comments.blockedKeywords"
    private static var source = ""
    private static var rules = PiliCommentKeywordRules("")
    static func filter(_ comments: [Comment], blocksGoods: Bool) -> [Comment] {
        let raw = UserDefaults.standard.string(forKey: key) ?? ""
        if raw != source { source = raw; rules = .init(raw) }
        return rules.filter(comments, blocksGoods: blocksGoods)
    }
}
