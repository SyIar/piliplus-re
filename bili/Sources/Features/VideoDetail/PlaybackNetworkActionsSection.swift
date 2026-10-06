import SwiftUI
import ChunUI

struct PlaybackNetworkActionsSection: View {
    let copiedMessage: String?
    let isProbingPlaybackCDN: Bool
    let probeMessage: String?
    let onCopyDiagnostics: () -> Void
    let onProbePlaybackCDN: () -> Void

    var body: some View {
        Section {
            Button(action: onCopyDiagnostics) {
                PiliLabel(copiedMessage ?? "复制诊断信息", systemImage: "doc.on.doc")
            }

            Button(action: onProbePlaybackCDN) {
                PiliLabel(isProbingPlaybackCDN ? "CDN 测速中" : "重新测速 CDN", systemImage: "speedometer")
            }
            .disabled(isProbingPlaybackCDN)

            if let probeMessage {
                Text(probeMessage)
                    .font(.cc.sm)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
