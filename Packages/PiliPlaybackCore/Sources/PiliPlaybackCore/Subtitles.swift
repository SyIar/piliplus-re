import Foundation

public struct SubtitleCue: Codable, Hashable, Sendable {
    public let from: Double
    public let to: Double
    public let content: String
    public init(from: Double, to: Double, content: String) {
        self.from = from; self.to = to; self.content = content
    }
    public var isValid: Bool { from.isFinite && to.isFinite && from >= 0 && to > from && !content.isEmpty }
}

/// A prefix maximum allows overlapping cues without scanning an entire film on every frame.
public struct SubtitleTimeline: Sendable {
    public let cues: [SubtitleCue]
    private let maximumEnds: [Double]
    public init(_ cues: [SubtitleCue]) {
        self.cues = cues.filter(\.isValid).sorted { $0.from < $1.from }
        var maximum = 0.0
        maximumEnds = self.cues.map { maximum = max(maximum, $0.to); return maximum }
    }
    public func active(at time: Double) -> [SubtitleCue] {
        guard time.isFinite, time >= 0 else { return [] }
        var low = 0, high = cues.count
        while low < high {
            let middle = (low + high) / 2
            if cues[middle].from <= time { low = middle + 1 } else { high = middle }
        }
        var index = low - 1
        var matches: [SubtitleCue] = []
        while index >= 0 && maximumEnds[index] > time {
            if cues[index].to > time { matches.append(cues[index]) }
            index -= 1
        }
        return matches.reversed()
    }
}

public enum SubtitleTextCodec {
    public static func parse(_ text: String) -> [SubtitleCue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        var cues: [SubtitleCue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.components(separatedBy: "\n")
            guard let index = lines.firstIndex(where: { $0.contains("-->") }), index + 1 < lines.count else { continue }
            let bounds = lines[index].components(separatedBy: "-->")
            guard bounds.count == 2, let start = timestamp(bounds[0]), let end = timestamp(bounds[1]) else { continue }
            let content = lines[(index + 1)...].joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
            let cue = SubtitleCue(from: start, to: end, content: content)
            if cue.isValid { cues.append(cue) }
        }
        return SubtitleTimeline(cues).cues
    }
    private static func timestamp(_ text: String) -> Double? {
        guard let first = text.split(whereSeparator: \.isWhitespace).first else { return nil }
        let fields = first.replacingOccurrences(of: ",", with: ".").split(separator: ":", omittingEmptySubsequences: false)
        let parts = fields.compactMap { Double($0) }
        guard fields.count == parts.count else { return nil }
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0 >= 0 && $0.isFinite }),
              parts.last! < 60, parts[parts.count - 2] < 60 else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
    public static func srt(_ cues: [SubtitleCue]) -> String {
        SubtitleTimeline(cues).cues.enumerated().map { index, cue in
            "\(index + 1)\n\(format(cue.from, separator: ",")) --> \(format(cue.to, separator: ","))\n\(cue.content)"
        }.joined(separator: "\n\n") + "\n"
    }
    public static func vtt(_ cues: [SubtitleCue]) -> String {
        "WEBVTT\n\n" + SubtitleTimeline(cues).cues.map { cue in
            "\(format(cue.from, separator: ".")) --> \(format(cue.to, separator: "."))\n\(cue.content)"
        }.joined(separator: "\n\n") + "\n"
    }
    private static func format(_ seconds: Double, separator: String) -> String {
        let millis = Int((min(seconds, 1_000_000_000_000) * 1000).rounded())
        return String(format: "%02d:%02d:%02d%@%03d", millis / 3_600_000, millis / 60_000 % 60, millis / 1000 % 60, separator, millis % 1000)
    }
}
