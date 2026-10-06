import SwiftUI
import ChunUI

struct PlayerPerformanceOverlayStartupGapsSection: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Startup gaps")
                .piliFont(.sm).fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text(message)
                .piliFont(.sm).monospacedDigit()
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
