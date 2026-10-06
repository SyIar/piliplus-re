import SwiftUI
import ChunUI

struct PlaybackNetworkHLSBridgeSourceRow: View {
    let snapshot: HLSBridgeSourceDiagnosticsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("#\(snapshot.order)")
                    .font(.cc.sm.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Text(snapshot.host)
                    .font(.cc.sm.monospaced())
                    .lineLimit(1)
                Spacer(minLength: 8)
                if snapshot.isSessionAvoided {
                    Text("避让")
                        .font(.cc.sm)
                        .foregroundStyle(Color.cc.warning)
                }
                Text(snapshot.averageMilliseconds.map { "\($0) ms" } ?? "-")
                    .font(.cc.sm.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(PlaybackNetworkDiagnosticFormat.hlsBridgeSourceSummary(snapshot))
                .font(.cc.sm)
                .foregroundStyle(snapshot.isSessionAvoided || snapshot.failureCount > 0 ? .orange : .secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
    }
}
