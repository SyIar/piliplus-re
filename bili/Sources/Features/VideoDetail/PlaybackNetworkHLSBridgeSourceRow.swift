import SwiftUI
import ChunUI

struct PlaybackNetworkHLSBridgeSourceRow: View {
    let snapshot: HLSBridgeSourceDiagnosticsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("#\(snapshot.order)")
                    .piliFont(.sm).monospacedDigit()
                    .foregroundStyle(.tertiary)
                Text(snapshot.host)
                    .piliFont(.sm).monospaced()
                    .lineLimit(1)
                Spacer(minLength: 8)
                if snapshot.isSessionAvoided {
                    Text("避让")
                        .piliFont(.sm)
                        .foregroundStyle(Color.cc.warning)
                }
                Text(snapshot.averageMilliseconds.map { "\($0) ms" } ?? "-")
                    .piliFont(.sm).monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Text(PlaybackNetworkDiagnosticFormat.hlsBridgeSourceSummary(snapshot))
                .piliFont(.sm)
                .foregroundStyle(snapshot.isSessionAvoided || snapshot.failureCount > 0 ? Color.cc.warning : .secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
    }
}
