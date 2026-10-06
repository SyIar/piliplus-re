import SwiftUI
import ChunUI

struct PlaybackNetworkDiagnosticMultilineRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .piliFont(.base)
            Text(value)
                .piliFont(.sm)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
