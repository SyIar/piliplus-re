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
                    .piliFont(.sm).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let decodeLogMessage = session.decodeLogMessage {
                PiliLabel(decodeLogMessage, systemImage: "cpu")
                    .piliFont(.sm).monospacedDigit()
                    .foregroundStyle(decodeLogMessage.localizedCaseInsensitiveContains("success") ? Color.cc.success : Color.cc.warning)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
