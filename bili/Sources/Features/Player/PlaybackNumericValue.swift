import Foundation

/// AVFoundation reports indefinite timestamps and unknown access-log metrics.
/// Converting those values directly to Int traps rather than throwing an error.
enum PlaybackNumericValue {
    static func seconds(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value < Double(Int.max) else { return nil }
        return value
    }

    static func integer(_ value: Double) -> Int {
        guard value.isFinite, value > 0, value < Double(Int.max) else { return 0 }
        return Int(value)
    }
}
