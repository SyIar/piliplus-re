import SwiftUI
import ChunUI

struct VideoDetailNetworkDiagnosticsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PiliLabel("网络诊断", systemImage: "waveform.path.ecg.rectangle")
                .font(.cc.sm.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
        .accessibilityLabel("打开网络诊断")
    }
}
