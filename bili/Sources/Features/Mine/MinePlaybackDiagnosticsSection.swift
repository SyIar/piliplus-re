import SwiftUI
import ChunUI

struct MinePlaybackDiagnosticsSection: View {
    @ObservedObject var libraryStore: LibraryStore
    var body: some View {
        Section("\u{64ad}\u{653e}\u{8bca}\u{65ad}\u{4e0e}\u{5b9e}\u{9a8c}") {
            NavigationLink {
                ResourceLoadingExperimentSettingsView(libraryStore: libraryStore)
            } label: {
                PlainSettingsNavigationRow(
                    title: "\u{52a0}\u{8f7d}\u{4f18}\u{5316}",
                    subtitle: "\u{7eed}\u{64ad}\u{9884}\u{70ed}\u{4e0e}\u{52a0}\u{8f7d}\u{8bca}\u{65ad}",
                )
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.playerPerformanceOverlayEnabled },
                    set: { libraryStore.setPlayerPerformanceOverlayEnabled($0) }
                )
            ) {
                MineSettingsLabel("\u{64ad}\u{653e}\u{6027}\u{80fd}\u{8bca}\u{65ad}", systemImage: "waveform.path.ecg.rectangle")
            }

            NavigationLink {
                PlayerPerformanceLogView()
            } label: {
                PlainSettingsNavigationRow(
                    title: "\u{64ad}\u{653e}\u{542f}\u{52a8}\u{65e5}\u{5fd7}",
                    subtitle: "\u{9996}\u{5e27}、\u{51c6}\u{5907}\u{548c}\u{7f13}\u{51b2}",
                )
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.playbackPlayableFallbackDeadlineExperimentEnabled },
                    set: { libraryStore.setPlaybackPlayableFallbackDeadlineExperimentEnabled($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    MineSettingsLabel("\u{5feb}\u{901f}\u{8d77}\u{64ad}（\u{5b9e}\u{9a8c}）", systemImage: "timer")
                    Text("\u{7b49}\u{5f85}\u{9ad8}\u{6e05}\u{8d85}\u{8fc7} 650 \u{6beb}\u{79d2}\u{65f6}，\u{5148}\u{4ee5}\u{53ef}\u{7528}\u{753b}\u{8d28}\u{64ad}\u{653e}。")
                        .piliFont(.sm)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(PlaybackPerformanceTestVideo.fixedSamples.enumerated()), id: \.element.id) { index, video in
                NavigationLink {
                    PlaybackPerformanceTestVideoView(testVideo: video)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        MineSettingsLabel("\u{6d4b}\u{8bd5}\u{89c6}\u{9891} \(index + 1)", systemImage: "play.rectangle")
                        Text(video.title)
                            .piliFont(.sm)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.videoRotationFrameReportOverlayEnabled },
                    set: { libraryStore.setVideoRotationFrameReportOverlayEnabled($0) }
                )
            ) {
                MineSettingsLabel("\u{65cb}\u{8f6c}\u{5e27}\u{62a5}\u{544a}", systemImage: "rotate.right")
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.videoDetailNavigationLatencyDiagnosticsEnabled },
                    set: { isEnabled in
                        if isEnabled {
                            PlaybackDetailPerformanceMonitor.shared.clear()
                        }
                        libraryStore.setVideoDetailNavigationLatencyDiagnosticsEnabled(isEnabled)
                    }
                )
            ) {
                MineSettingsLabel("\u{8be6}\u{60c5}\u{6253}\u{5f00}\u{8017}\u{65f6}", systemImage: "stopwatch")
            }

            Toggle(
                isOn: Binding(
                    get: { libraryStore.showsVideoDetailNetworkDiagnosticsButton },
                    set: { libraryStore.setShowsVideoDetailNetworkDiagnosticsButton($0) }
                )
            ) {
                MineSettingsLabel("\u{89c6}\u{9891}\u{8be6}\u{60c5}\u{7f51}\u{7edc}\u{8bca}\u{65ad}", systemImage: "stethoscope")
            }

        }
    }
}
