import SwiftUI

struct PlayerNativeTimeLabel: View {
    @ObservedObject var clock: PlayerPlaybackClock
    let metrics: PlayerNativeControlMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(currentText)
            Text(durationText).foregroundStyle(.secondary)
        }
        .font(metrics.timeFont)
        .biliLiquidGlassForeground(shadowOpacity: 0.20)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .accessibilityLabel("\u{64ad}\u{653e}\u{65f6}\u{95f4} \(fullTimeText)")
    }

    private var currentText: String {
        BiliFormatters.duration(PlaybackNumericValue.integer(clock.displayCurrentTime.rounded()))
    }

    private var durationText: String {
        guard let duration = clock.duration, duration > 0 else { return "--:--" }
        return BiliFormatters.duration(PlaybackNumericValue.integer(duration.rounded()))
    }

    private var fullTimeText: String { "\(currentText) / \(durationText)" }
}
