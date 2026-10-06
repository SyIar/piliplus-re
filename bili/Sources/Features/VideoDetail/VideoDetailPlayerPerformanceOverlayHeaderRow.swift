import SwiftUI
import ChunUI
import UIKit

struct PlayerPerformanceOverlayHeaderRow: View {
    let metricsID: String
    let copyTextProvider: () -> String?
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 6) {
            PiliIcon(systemName: "waveform.path.ecg.rectangle")
                .font(.cc.sm.weight(.bold))
            Text("播放性能")
                .font(.cc.sm.weight(.semibold))
            Spacer(minLength: 8)
            Text(PlayerPerformanceOverlayFormatting.shortMetricsID(metricsID))
                .font(.cc.sm.monospaced())
                .foregroundStyle(.secondary)
            if copyTextProvider() != nil {
                Button {
                    guard let copyText = copyTextProvider() else { return }
                    UIPasteboard.general.string = copyText
                    didCopy = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        didCopy = false
                    }
                } label: {
                    PiliIcon(systemName: didCopy ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.cc.sm.weight(.semibold))
                        .foregroundStyle(didCopy ? .green : .secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(didCopy ? "已复制诊断日志" : "复制诊断日志")
            }
        }
    }
}
