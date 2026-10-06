import SwiftUI
import ChunUI

struct PlayerPerformanceOverlayStartupLines: View {
    let session: PlayerPerformanceSession

    var body: some View {
        Group {
            if let startupBreakdownMessage = session.startupBreakdownMessage {
                PlayerPerformanceOverlayStartupBreakdownSection(message: startupBreakdownMessage)
            }

            if let prepareStageMessage = session.prepareStageMessage {
                PlayerPerformanceOverlayPrepareStagesSection(message: prepareStageMessage)
            }

            if let startupGapMessage = session.startupGapMessage {
                PlayerPerformanceOverlayStartupGapsSection(message: startupGapMessage)
            }
        }
    }
}

private struct PlayerPerformanceOverlayStartupBreakdownSection: View {
    let message: String

    private var metrics: [PrepareStageMetric] {
        PlayerPerformanceOverlayFormatting.startupBreakdownMetrics(from: message)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            PiliLabel("Startup breakdown", systemImage: "chart.bar.xaxis")
                .piliFont(.sm).fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if metrics.isEmpty {
                Text(message)
                    .piliFont(.sm).monospaced()
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6)
                    ],
                    alignment: .leading,
                    spacing: 4
                ) {
                    ForEach(metrics, id: \.name) { metric in
                        PlayerPerformanceOverlayStartupBreakdownMetricRow(metric: metric)
                    }
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
}

private struct PlayerPerformanceOverlayStartupBreakdownMetricRow: View {
    let metric: PrepareStageMetric

    var body: some View {
        HStack(spacing: 3) {
            Text(metric.name)
                .piliFont(.sm)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 2)

            Text(metric.value)
                .piliFont(.smBold).monospaced()
                .foregroundStyle(
                    PlayerPerformanceOverlayFormatting.metricColor(
                        PlayerPerformanceOverlayFormatting.millisecondsValue(from: metric.value)
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }
}
