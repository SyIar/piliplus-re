import SwiftUI
import ChunUI

struct PlayerPerformanceOverlayTerminalSection: View {
    let session: PlayerPerformanceSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let qualitySupplementMessage = session.qualitySupplementMessage {
                Text(qualitySupplementMessage)
                    .piliFont(.sm).monospacedDigit()
                    .foregroundStyle(Color.cc.warning)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let failure = session.failureMessage {
                Text(failure)
                    .piliFont(.sm)
                    .foregroundStyle(Color.cc.destructive)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
