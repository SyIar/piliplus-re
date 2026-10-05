import SwiftUI
import PiliPlaybackCore

struct PiliSubtitlePreviewFixture: View {
    @StateObject private var controller = PiliSubtitleController()
    @StateObject private var clock = PlayerPlaybackClock()
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [.indigo, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                PiliSubtitleOverlay(controller: controller, clock: clock)
            }.frame(height: 180)
            PiliSubtitleSettingsView(controller: controller)
        }
        .task {
            AppOrientationLock.restorePortrait()
            if UITestFixtureScenario.resetsPersistedState {
                UserDefaults.standard.set("on", forKey: "piliplus.subtitle.mode")
                UserDefaults.standard.set("#FFFFFF", forKey: "piliplus.subtitle.textColor")
                controller.setDualEnabled(false)
            }
            controller.loadOffline([
                .init(track: .init(lan: "zh", lanDoc: "中文", subtitleURL: nil, type: 0), cues: [.init(from: 0, to: 5, content: "在山海之间，遇见一场日落")]),
                .init(track: .init(lan: "en", lanDoc: "English", subtitleURL: nil, type: 0), cues: [.init(from: 1, to: 6, content: "Meet the sunset between mountains and sea.")])
            ])
            clock.update(time: 2, duration: 30, force: true)
        }
    }
}
