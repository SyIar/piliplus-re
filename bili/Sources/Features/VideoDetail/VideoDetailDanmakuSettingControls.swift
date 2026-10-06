import SwiftUI
import ChunUI

struct DanmakuSettingsSlider: View {
    let title: String
    let systemImage: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PiliLabel(title, systemImage: systemImage)
                Spacer()
                Text(valueText)
                    .font(.cc.sm.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
        .padding(.vertical, 2)
    }
}
