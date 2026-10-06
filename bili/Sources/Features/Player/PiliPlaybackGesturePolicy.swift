import CoreGraphics

nonisolated enum PiliPlaybackGesturePolicy {
    static func seekOffset(x: CGFloat, width: CGFloat, enabled: Bool) -> Double? {
        guard enabled, width > 0, x >= 0, x <= width else { return nil }
        if x < width * 0.3 { return -10 }
        if x > width * 0.7 { return 10 }
        return nil
    }
    static func isCenter(x: CGFloat, width: CGFloat) -> Bool {
        width > 0 && x >= width * 0.35 && x <= width * 0.65
    }
    static func changesFullscreen(startX: CGFloat, size: CGSize, translation: CGSize, fullscreen: Bool) -> Bool {
        guard isCenter(x: startX, width: size.width), abs(translation.height) >= 60,
              abs(translation.height) > abs(translation.width) * 3 else { return false }
        return fullscreen ? translation.height > 0 : translation.height < 0
    }
}
