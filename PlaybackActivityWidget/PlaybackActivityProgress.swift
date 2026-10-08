import SwiftUI

struct PlaybackActivityProgress: View {
    let state: PlaybackActivityAttributes.ContentState

    var body: some View {
        if state.duration > 0 {
            if state.isPlaying, state.rate > 0 {
                let start = state.updatedAt.addingTimeInterval(-state.elapsed / state.rate)
                ProgressView(timerInterval: start...start.addingTimeInterval(state.duration / state.rate), countsDown: false)
                    .tint(.blue)
            } else {
                ProgressView(value: state.progress).tint(.blue)
            }
        }
    }
}
