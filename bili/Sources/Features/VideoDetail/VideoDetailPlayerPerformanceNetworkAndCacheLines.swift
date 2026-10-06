import SwiftUI
import ChunUI

struct PlayerPerformanceOverlayNetworkAndCacheLines: View {
    let session: PlayerPerformanceSession

    var body: some View {
        Group {
            if let cdnHost = session.cdnHostMessage {
                PiliLabel(cdnHost, systemImage: "network")
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let networkMessage = session.networkMessage {
                Text(networkMessage)
                    .font(.cc.sm.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let hlsStartupMessage = session.hlsStartupMessage {
                Text(hlsStartupMessage)
                    .font(.cc.sm.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let accessLogMessage = session.accessLogMessage {
                Text(accessLogMessage)
                    .font(.cc.sm.monospacedDigit())
                    .foregroundStyle((session.accessLogStallCount ?? 0) > 0 ? .orange : .secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let mediaCacheMessage = session.mediaCacheMessage {
                Text(mediaCacheMessage)
                    .font(.cc.sm.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let manifestStageMessage = session.manifestStageMessage {
                Text(manifestStageMessage)
                    .font(.cc.sm.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
