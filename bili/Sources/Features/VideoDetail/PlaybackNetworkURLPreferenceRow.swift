import SwiftUI
import ChunUI

struct PlaybackNetworkURLPreferenceRow: View {
    let snapshot: PlaybackURLPreferenceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(snapshot.host)
                    .piliFont(.sm).monospaced()
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(snapshot.averageMilliseconds) ms")
                    .piliFont(.sm).monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Text(PlaybackNetworkDiagnosticFormat.playbackURLPreferenceSummary(snapshot))
                .piliFont(.sm)
                .foregroundStyle(snapshot.failureCount > 0 ? Color.cc.warning : .secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
    }
}
