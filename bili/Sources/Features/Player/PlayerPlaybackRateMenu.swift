import SwiftUI

struct PlayerPlaybackRateMenu: View {
    let rate: BiliPlaybackRate
    let onSelect: (BiliPlaybackRate) -> Void

    var body: some View {
        Menu {
            ForEach(BiliPlaybackRate.allCases) { option in
                Button(option.title) { onSelect(option) }
            }
        } label: {
            Text(rate.title)
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\u{64ad}\u{653e}\u{901f}\u{5ea6}")
        .accessibilityValue(rate.title)
        .accessibilityIdentifier("ui.player.rate")
    }
}
