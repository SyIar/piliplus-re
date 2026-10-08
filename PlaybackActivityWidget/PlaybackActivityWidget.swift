import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PlaybackActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlaybackActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Text(context.state.isPlaying ? "\u{25b6}" : "\u{23f8}")
                        .font(.title2).frame(width: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.title).font(.headline).lineLimit(2)
                        Text(context.state.author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                PlaybackActivityProgress(state: context.state)
            }
            .padding(16)
            .foregroundStyle(.white)
            .activityBackgroundTint(.black.opacity(0.8))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.isPlaying ? "\u{25b6}" : "\u{23f8}").font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isPlaying ? "\u{64ad}\u{653e}\u{4e2d}" : "\u{5df2}\u{6682}\u{505c}")
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.title).font(.headline).lineLimit(2)
                        Text(context.state.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        PlaybackActivityProgress(state: context.state)
                    }
                }
            } compactLeading: {
                Text(context.state.isPlaying ? "\u{25b6}" : "\u{23f8}")
            } compactTrailing: {
                ProgressView(value: context.state.progress).progressViewStyle(.circular).frame(width: 18)
            } minimal: {
                Text(context.state.isPlaying ? "\u{25b6}" : "\u{23f8}")
            }
            .keylineTint(.blue)
        }
    }
}
