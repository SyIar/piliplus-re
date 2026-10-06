import Foundation

public enum DanmakuMerge {
    public struct Sample: Sendable {
        public let id: String
        public let time: Double
        public let text: String
        public let style: String
        public let sender: String?
        public init(id: String, time: Double, text: String, style: String, sender: String?) {
            self.id = id; self.time = time; self.text = text; self.style = style; self.sender = sender
        }
    }
    public struct Group: Equatable, Sendable {
        public let representativeID: String
        public var count: Int
    }
    private struct Key: Hashable { let window: Int; let text: String; let style: String }

    /// Fixed video-time windows keep seek/reload results deterministic. Filtered
    /// samples must be removed before calling. Unknown authors count by message ID.
    public static func groups(_ samples: [Sample], window: Double = 15) -> [Group] {
        guard window.isFinite, window >= 1 else { return [] }
        var result: [Group] = [], indexes: [Key: Int] = [:], senders: [Key: Set<String>] = [:], seenIDs = Set<String>()
        let sorted = samples.filter { $0.time.isFinite && $0.time >= 0 && $0.time < Double(Int.max) / 2 && !$0.text.isEmpty }
            .sorted { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
        for sample in sorted {
            guard seenIDs.insert(sample.id).inserted else { continue }
            let key = Key(window: Int(sample.time / window), text: sample.text, style: sample.style)
            let author = sample.sender.flatMap { $0.isEmpty ? nil : "sender:" + $0 } ?? "message:" + sample.id
            if let index = indexes[key] {
                if senders[key, default: []].insert(author).inserted { result[index].count += 1 }
            } else {
                indexes[key] = result.count; senders[key] = [author]
                result.append(Group(representativeID: sample.id, count: 1))
            }
        }
        return result
    }
}
