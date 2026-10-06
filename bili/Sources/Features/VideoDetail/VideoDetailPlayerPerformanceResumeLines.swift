import SwiftUI
import ChunUI

struct PlayerPerformanceOverlayResumeLines: View {
    let session: PlayerPerformanceSession

    var body: some View {
        Group {
            if let resumeDecisionMessage = session.resumeDecisionMessage {
                PiliLabel(resumeDecisionMessage, systemImage: "clock.arrow.circlepath")
                    .font(.cc.sm.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let resumeRecoveryMessage = session.resumeRecoveryMessage {
                PiliLabel(resumeRecoveryMessage, systemImage: "checkmark.circle")
                    .font(.cc.sm.monospacedDigit())
                    .foregroundStyle(session.resumeRecoverySlowCount > 0 ? .orange : .secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
