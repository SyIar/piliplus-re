import SwiftUI
import ChunUI

struct PlayerPerformanceOverlayDetailAndEngineLines: View {
    let session: PlayerPerformanceSession
    let playerViewModel: PlayerStateViewModel?

    var body: some View {
        Group {
            if let detailSource = session.detailSourceMessage {
                PiliLabel(detailSource, systemImage: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let diagnostics = playerViewModel?.engineDiagnostics {
                Text(diagnostics.compactDescription)
                    .font(.cc.sm.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let decodeLogMessage = session.decodeLogMessage {
                PiliLabel(decodeLogMessage, systemImage: "cpu")
                    .font(.cc.sm.monospacedDigit())
                    .foregroundStyle(decodeLogMessage.localizedCaseInsensitiveContains("success") ? .green : .orange)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
