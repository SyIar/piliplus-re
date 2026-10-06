import SwiftUI
import ChunUI

extension MinePlaybackSettingsView {
    var playbackPreferenceSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MineSettingsLabel("当前策略", systemImage: "wand.and.stars")
                    .font(.cc.base.weight(.semibold))
                Spacer(minLength: 8)
                Text(libraryStore.playbackAutoOptimizationMode.title)
                    .font(.cc.sm.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(libraryStore.playbackAutoOptimizationMode.detail)
                .font(.cc.sm)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                MinePlaybackPreferenceChip(
                    title: LibraryStore.videoQualityTitle(libraryStore.preferredVideoQuality),
                    systemImage: "play.rectangle"
                )
                MinePlaybackPreferenceChip(
                    title: libraryStore.videoCodecPreference.title,
                    systemImage: "film.stack"
                )
                if libraryStore.forceHardwareDecodeEnabled {
                    MinePlaybackPreferenceChip(
                        title: "硬解优先",
                        systemImage: "cpu"
                    )
                }
                MinePlaybackPreferenceChip(
                    title: libraryStore.dolbyVisionRenderingPolicy.title,
                    systemImage: "sparkles.tv"
                )
                MinePlaybackPreferenceChip(
                    title: BiliPlaybackRate(rawValue: libraryStore.defaultPlaybackRate)?.title ?? "\(libraryStore.defaultPlaybackRate)x",
                    systemImage: "speedometer"
                )
            }
        }
        .padding(.vertical, 4)
    }
}
