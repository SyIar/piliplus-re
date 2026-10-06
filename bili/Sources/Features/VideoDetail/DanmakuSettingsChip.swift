import SwiftUI
import ChunUI

struct DanmakuSettingsChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        PiliLabel(title, systemImage: systemImage)
            .font(.cc.sm.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .ccGlassEffect(.capsule)
            .overlay {
                Capsule()
                    .stroke(Color(.separator).opacity(0.10), lineWidth: 0.5)
            }
    }
}
