import SwiftUI
import ChunUI

struct PlayerPerformanceOverlayStartupGapsSection: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Startup gaps")
                .font(.cc.sm.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.cc.sm.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(
            PlayerPerformanceOverlayFormatting.sectionBackground,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }
}
