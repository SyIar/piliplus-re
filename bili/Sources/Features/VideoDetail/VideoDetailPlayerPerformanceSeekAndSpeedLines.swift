import SwiftUI
import ChunUI

struct PlayerPerformanceOverlaySeekAndSpeedLines: View {
    let session: PlayerPerformanceSession

    var body: some View {
        Group {
            if let seekMessage = session.seekMessage {
                PiliLabel(seekMessage, systemImage: "forward.frame")
                    .piliFont(.sm).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let seekRecoveryMessage = session.seekRecoveryMessage {
                PiliLabel(seekRecoveryMessage, systemImage: "speedometer")
                    .piliFont(.sm).monospacedDigit()
                    .foregroundStyle(session.seekRecoverySlowCount > 0 ? Color.cc.warning : .secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let speedBoostMessage = session.speedBoostMessage {
                PiliLabel(speedBoostMessage, systemImage: "forward.fill")
                    .piliFont(.sm).monospacedDigit()
                    .foregroundStyle(session.speedBoostInterruptionCount > 0 ? Color.cc.warning : .secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
