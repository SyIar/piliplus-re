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
                    .piliFont(.sm).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let hlsStartupMessage = session.hlsStartupMessage {
                Text(hlsStartupMessage)
                    .piliFont(.sm).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let accessLogMessage = session.accessLogMessage {
                Text(accessLogMessage)
                    .piliFont(.sm).monospacedDigit()
                    .foregroundStyle((session.accessLogStallCount ?? 0) > 0 ? Color.cc.warning : .secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let mediaCacheMessage = session.mediaCacheMessage {
                Text(mediaCacheMessage)
                    .piliFont(.sm).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let manifestStageMessage = session.manifestStageMessage {
                Text(manifestStageMessage)
                    .piliFont(.sm).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
