import SwiftUI

struct PlayerInlineQuickControls: View {
    @ObservedObject var player: PlayerStateViewModel
    let subtitles: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            PiliGlassPlayerButton(symbol: "captions.bubble", title: "\u{5b57}\u{5e55}", grouped: true, action: subtitles)
            PlayerPlaybackRateMenu(rate: player.playbackRate, onSelect: player.setPlaybackRate)
        }
    }
}
