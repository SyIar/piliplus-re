import SwiftUI
import ChunUI

struct PlayerPerformanceSampleGroupRow: View {
    let group: PlayerPerformanceSampleGroup
    let isRecommended: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlayerPerformanceSampleGroupHeader(
                title: group.title,
                isRecommended: isRecommended,
                headerColor: headerColor
            )

            Text(group.subtitle)
                .piliFont(.sm)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            PlayerPerformanceMetricGrid(group: group)

            if group.issueCount > 0 {
                Text(issueSummary)
                    .piliFont(.sm)
                    .foregroundStyle(issueColor)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private var headerColor: Color {
        if group.failedCount > 0 || group.slowStartupCount > 1 || group.accessLogStallCount > 0 {
            return Color.cc.warning
        }
        return isRecommended ? Color.cc.success : .primary
    }

    private var issueColor: Color {
        group.failedCount > 0 ? Color.cc.destructive : Color.cc.warning
    }

    private var issueSummary: String {
        var parts: [String] = []
        if group.slowStartupCount > 0 {
            parts.append("慢启动 \(group.slowStartupCount)")
        }
        if group.failedCount > 0 {
            parts.append("失败 \(group.failedCount)")
        }
        if group.bufferCount > 0 {
            parts.append("缓冲 \(group.bufferCount)")
        }
        if group.seekRecoverySlowCount > 0 {
            parts.append("Seek 慢恢复 \(group.seekRecoverySlowCount)")
        }
        if group.accessLogStallCount > 0 {
            parts.append("系统 Stall \(group.accessLogStallCount)")
        }
        if group.speedBoostInterruptionCount > 0 {
            parts.append("倍速中断 \(group.speedBoostInterruptionCount)")
        }
        return parts.joined(separator: " · ")
    }
}

private struct PlayerPerformanceSampleGroupHeader: View {
    let title: String
    let isRecommended: Bool
    let headerColor: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            PiliLabel(title, systemImage: isRecommended ? "checkmark.seal.fill" : "chart.bar.xaxis")
                .piliFont(.base).fontWeight(.semibold)
                .foregroundStyle(headerColor)
                .lineLimit(1)

            Spacer(minLength: 8)

            if isRecommended {
                Text("样本较优")
                    .piliFont(.sm).fontWeight(.semibold)
                    .foregroundStyle(Color.cc.success)
            }
        }
    }
}
