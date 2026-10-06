import SwiftUI
import ChunUI
import UIKit

struct VideoRotationFrameReportFloatingWindow: View {
    @ObservedObject private var store = VideoRotationFrameReportStore.shared
    let metricsID: String
    let contentInsets: EdgeInsets

    @State private var dismissedReportID: UUID?
    @State private var didCopy = false

    var body: some View {
        if let report = store.latestReport,
           report.metricsID == metricsID,
           dismissedReportID != report.id {
            VStack {
                HStack {
                    Spacer(minLength: 16)
                    panel(for: report)
                        .padding(.top, max(contentInsets.top + 12, 18))
                        .padding(.trailing, max(contentInsets.trailing + 12, 14))
                }
                Spacer()
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .animation(.easeInOut(duration: 0.18), value: report.id)
        }
    }

    private func panel(for report: VideoRotationFrameReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PiliLabel("旋转报告", systemImage: "rotate.right")
                    .piliFont(.sm).fontWeight(.semibold)

                Spacer(minLength: 8)

                Button {
                    UIPasteboard.general.string = report.copyText
                    didCopy = true
                } label: {
                    PiliIcon(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .piliFont(.sm).fontWeight(.semibold)
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(didCopy ? "已复制旋转报告" : "复制旋转报告")

                Button {
                    dismissedReportID = report.id
                } label: {
                    PiliIcon(systemName: "xmark")
                        .piliFont(.sm).fontWeight(.semibold)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭旋转报告")
            }

            HStack(spacing: 10) {
                metric("P95", value("p95", in: report.message))
                metric("MAX", value("max", in: report.message))
                metric("Hitch", value("hitch", in: report.message))
                metric("Drop", value("drop", in: report.message))
            }
            .piliFont(.sm).monospacedDigit()

            Text(didCopy ? "已复制完整日志" : "点复制可发送完整日志")
                .piliFont(.sm)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 260, alignment: .leading)
        .piliGlassCard(radius: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
        .onChange(of: report.id) { _, _ in
            didCopy = false
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func value(_ key: String, in message: String) -> String {
        message
            .split(separator: " ")
            .first(where: { $0.hasPrefix("\(key)=") })
            .map { String($0.dropFirst(key.count + 1)) } ?? "-"
    }
}
