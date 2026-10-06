import SwiftUI
import ChunUI

struct PlayerPerformanceOverlaySamplesSection: View {
    let samples: [PlayerStartupPerformanceSample]

    private var comparableSamples: [PlayerStartupPerformanceSample] {
        PlayerPerformanceOverlayFormatting.comparableStartupSamples(from: samples)
    }

    private var stableSamples: [PlayerStartupPerformanceSample] {
        PlayerPerformanceOverlayFormatting.stableStartupSamples(from: samples)
    }

    private var summaries: [StartupSampleMetricSummary] {
        PlayerPerformanceOverlayFormatting.startupSampleSummaries(from: stableSamples)
    }

    private var filterText: String? {
        PlayerPerformanceOverlayFormatting.startupSampleFilterText(for: samples)
    }

    private var ignoredSampleCount: Int {
        max(samples.count - comparableSamples.count, 0)
    }

    private var coldSampleCount: Int {
        max(comparableSamples.count - stableSamples.count, 0)
    }

    private var sampleNoteText: String? {
        guard let filterText else { return nil }
        var parts = [filterText]
        if coldSampleCount > 0 {
            parts.append("统计已排除 \(coldSampleCount) 条冷启动样本")
        }
        if ignoredSampleCount > 0 {
            parts.append("另忽略 \(ignoredSampleCount) 条不同清晰度/编码样本")
        }
        if coldSampleCount == 0 && ignoredSampleCount == 0 {
            parts.append("样本一致")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                PiliLabel("稳定 \(stableSamples.count)/\(comparableSamples.count) 次首帧", systemImage: "clock.arrow.circlepath")
                    .piliFont(.sm).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let latest = samples.last?.firstFramePlayerMilliseconds {
                    Text("last \(PlayerPerformanceOverlayFormatting.millisecondsText(latest))")
                        .piliFont(.sm).monospacedDigit().fontWeight(.semibold)
                        .foregroundStyle(PlayerPerformanceOverlayFormatting.metricColor(latest))
                }
            }

            if summaries.isEmpty {
                Text("反复进入同一个视频后会自动累计样本")
                    .piliFont(.sm)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 48), spacing: 6),
                        GridItem(.fixed(44), spacing: 6),
                        GridItem(.fixed(44), spacing: 6),
                        GridItem(.fixed(44), spacing: 6)
                    ],
                    alignment: .leading,
                    spacing: 4
                ) {
                    sampleHeader("项")
                    sampleHeader("min")
                    sampleHeader("avg")
                    sampleHeader("max")

                    ForEach(summaries) { summary in
                        Text(summary.title)
                            .piliFont(.sm)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        sampleValue(summary.minimumMilliseconds)
                        sampleValue(summary.averageMilliseconds)
                        sampleValue(summary.maximumMilliseconds)
                    }
                }

                if let sampleNoteText {
                    Text(sampleNoteText)
                        .piliFont(.sm)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(
            PlayerPerformanceOverlayFormatting.sectionBackground,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }

    private func sampleHeader(_ text: String) -> some View {
        Text(text)
            .piliFont(.smBold)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }

    private func sampleValue(_ milliseconds: Int) -> some View {
        Text(PlayerPerformanceOverlayFormatting.millisecondsText(milliseconds))
            .piliFont(.smBold).monospaced()
            .foregroundStyle(PlayerPerformanceOverlayFormatting.metricColor(milliseconds))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }
}
