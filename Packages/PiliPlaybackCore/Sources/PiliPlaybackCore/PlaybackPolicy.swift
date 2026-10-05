import Foundation

/// User-visible playback order, independent of the rendering engine.
public enum PlaybackOrder: String, CaseIterable, Codable, Sendable {
    case stop, repeatOne, sequential, repeatList, related
}

public enum PlaybackEndAction: Equatable, Sendable {
    case stop, replay, advance(Int), loadRelated
}

public enum PlaybackEndPolicy {
    public static func resolve(
        order: PlaybackOrder,
        currentIndex: Int?,
        count: Int,
        sleepTimerStops: Bool
    ) -> PlaybackEndAction {
        guard !sleepTimerStops else { return .stop }
        if order == .stop { return .stop }
        if order == .repeatOne { return .replay }
        if let currentIndex, currentIndex >= 0, currentIndex < count {
            if currentIndex + 1 < count { return .advance(currentIndex + 1) }
            if order == .repeatList { return count == 1 ? .replay : .advance(0) }
        }
        return order == .related ? .loadRelated : .stop
    }
}

/// Wall-clock deadlines deliberately do not depend on video position or playback rate.
public struct SleepTimerPolicy: Codable, Equatable, Sendable {
    public enum State: Codable, Equatable, Sendable {
        case off
        case scheduled(deadline: Date, finishCurrent: Bool)
        case waitingForEnd
        case stopped
    }

    public private(set) var state: State = .off
    public init() {}
    public var preventsAutomaticPlayback: Bool { state == .stopped }

    public mutating func schedule(deadline: Date, finishCurrent: Bool) {
        state = .scheduled(deadline: deadline, finishCurrent: finishCurrent)
    }
    public mutating func stopAfterCurrent() { state = .waitingForEnd }
    public mutating func cancel() { state = .off }

    /// Returns true when the caller should pause, including after background suspension.
    @discardableResult
    public mutating func tick(now: Date, hasActiveItem: Bool) -> Bool {
        if state == .waitingForEnd && !hasActiveItem {
            state = .stopped
            return true
        }
        guard case let .scheduled(deadline, finishCurrent) = state, now >= deadline else {
            return state == .stopped
        }
        state = finishCurrent && hasActiveItem ? .waitingForEnd : .stopped
        return state == .stopped
    }

    /// The deadline is checked before autoplay, even when its timer callback arrives late.
    public mutating func playbackEnded(now: Date) -> Bool {
        tick(now: now, hasActiveItem: true)
        if state == .waitingForEnd { state = .stopped }
        return state == .stopped
    }
}

public struct SkipSegment: Equatable, Sendable {
    public let id: String
    public let start: TimeInterval
    public let end: TimeInterval
    public init(id: String, start: TimeInterval, end: TimeInterval) {
        self.id = id; self.start = start; self.end = end
    }
}

public enum SegmentSkipPolicy {
    /// Also handles seeking directly inside a segment; invalid intervals are ignored.
    public static func destination(at time: TimeInterval, segments: [SkipSegment]) -> TimeInterval? {
        guard time.isFinite, time >= 0 else { return nil }
        let valid = segments.filter { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start }
        guard var target = valid.filter({ $0.start <= time && time < $0.end }).map(\.end).max() else { return nil }
        // Merge overlapping ranges to avoid a chain of audible seeks.
        while let next = valid.filter({ $0.start <= target && target < $0.end }).map(\.end).max() {
            target = next
        }
        return target
    }
}
