import SwiftUI
import ChunUI

struct PlayerPerformanceSessionHeader: View {
    let session: PlayerPerformanceSession

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(session.title ?? session.metricsID)
                .font(.cc.base.weight(.semibold))
                .lineLimit(2)

            Spacer(minLength: 8)

            Text(session.lastUpdatedAt, style: .time)
                .font(.cc.sm.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

struct PlayerPerformanceSessionSummary: View {
    let session: PlayerPerformanceSession

    var body: some View {
        HStack(spacing: 8) {
            PiliLabel("\(session.bufferCount) 次缓冲", systemImage: "hourglass")

            if session.resumeRecoveryCount > 0 {
                PiliLabel("\(session.resumeRecoveryCount) 次续播验证", systemImage: "checkmark.circle")
            }

            if session.seekRecoveryCount > 0 {
                PiliLabel("\(session.seekRecoveryCount) 次 Seek 恢复", systemImage: "speedometer")
            }

            if let detailSourceMessage = session.detailSourceMessage {
                Text(detailSourceMessage)
                    .lineLimit(1)
            }

            if let selectedQualityMessage = session.selectedQualityMessage {
                Text(selectedQualityMessage)
                    .lineLimit(1)
            }
        }
        .font(.cc.sm)
        .foregroundStyle(summaryColor)
    }

    private var summaryColor: Color {
        session.bufferCount > 0
            || session.resumeRecoverySlowCount > 0
            || session.seekRecoverySlowCount > 0
            || (session.accessLogStallCount ?? 0) > 0 ? .orange : .secondary
    }
}

struct PlayerPerformanceSessionTimeline: View {
    let session: PlayerPerformanceSession

    var body: some View {
        if !session.timeline.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("时间线")
                    .font(.cc.sm.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(session.timeline.suffix(6)) { entry in
                    Text(entry.compactDescription)
                        .font(.cc.sm.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct PlayerPerformanceSessionFailureLabel: View {
    let session: PlayerPerformanceSession

    var body: some View {
        if let failureMessage = session.failureMessage {
            PiliLabel(failureMessage, systemImage: "exclamationmark.triangle")
                .font(.cc.sm)
                .foregroundStyle(Color.cc.destructive)
                .lineLimit(2)
        }
    }
}
