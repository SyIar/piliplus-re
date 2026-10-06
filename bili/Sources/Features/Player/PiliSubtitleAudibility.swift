import AVFAudio
import Combine
import SwiftUI

extension EnvironmentValues { @Entry var piliPlaybackIsMuted = false }

@MainActor
final class PiliSystemAudibility: ObservableObject {
    static let shared = PiliSystemAudibility()
    @Published private(set) var isSilent = false
    private var observation: NSKeyValueObservation?
    private init() {
        let session = AVAudioSession.sharedInstance()
        isSilent = session.outputVolume <= 0
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            let silent = session.outputVolume <= 0
            Task { @MainActor [weak self] in if self?.isSilent != silent { self?.isSilent = silent } }
        }
    }
}

struct PiliOfflineSubtitleLayer: View {
    let controller: PiliSubtitleController
    @ObservedObject var player: PlayerStateViewModel
    var body: some View {
        PiliSubtitleOverlay(controller: controller, clock: player.playbackClock)
            .environment(\.piliPlaybackIsMuted, player.isMuted || player.volume <= 0)
    }
}
