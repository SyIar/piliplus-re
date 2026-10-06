import SwiftUI
import ChunUI

extension MinePlaybackSettingsView {
    @ViewBuilder
    var playbackURLPreferenceSummary: some View {
        if let bestSnapshot = playbackURLPreferenceSnapshots.first {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    MineSettingsLabel("真实播放优先", systemImage: "dot.radiowaves.left.and.right")
                        .piliFont(.sm).fontWeight(.semibold)
                    Spacer(minLength: 8)
                    Text(bestSnapshot.host)
                        .piliFont(.sm).monospaced()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text("根据 AVPlayer 实际码率、传输耗时和新增 stall，在接口候选地址内自动修正 CDN Host 排序。")
                    .piliFont(.sm)
                    .foregroundStyle(.secondary)

                DisclosureGroup(isExpanded: $isShowingPlaybackURLPreferenceDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(playbackURLPreferenceSnapshots) { snapshot in
                            playbackURLPreferenceSnapshotRow(snapshot)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    MineSettingsLabel("真实播放排行", systemImage: "list.bullet.rectangle")
                        .piliFont(.sm)
                }
            }
            .padding(.vertical, 2)
        }
    }

    func playbackURLPreferenceSnapshotRow(_ snapshot: PlaybackURLPreferenceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(snapshot.host)
                    .piliFont(.sm).monospaced()
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(snapshot.averageMilliseconds) ms")
                    .piliFont(.sm).monospacedDigit()
            }

            HStack(spacing: 8) {
                Text(snapshot.networkTitle)
                Text(playbackURLThroughputText(snapshot.averageKilobytesPerSecond))
                Text("失败 \(snapshot.failureRatePercent)%")
                Text("\(snapshot.attemptCount) 样本")
            }
            .piliFont(.sm)
            .foregroundStyle(snapshot.failureCount > 0 ? Color.cc.warning : .secondary)
            .lineLimit(1)

            Text("最近 \(snapshot.lastUpdatedAt.formatted(date: .abbreviated, time: .shortened))")
                .piliFont(.sm)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    func playbackURLThroughputText(_ kilobytesPerSecond: Int) -> String {
        guard kilobytesPerSecond > 0 else { return "吞吐 -" }
        if kilobytesPerSecond >= 1024 {
            return String(format: "%.1f MB/s", Double(kilobytesPerSecond) / 1024)
        }
        return "\(kilobytesPerSecond) KB/s"
    }
}
