import SwiftUI
import UIKit
import ChunUI

struct MineAboutSection: View {
    @Environment(\.openURL) private var openURL

    private static let projectURL = URL(string: "https://github.com/SyIar/piliplus-re")!

    var body: some View {
        Section("关于") {
            HStack {
                PiliLabel("版本", systemImage: "info.circle")
                Spacer(minLength: 12)
                Text(versionText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            projectRow
                .contentShape(Rectangle())
                .gesture(projectAddressGesture)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("轻点打开项目地址，长按复制")
                .accessibilityAction(named: "复制项目地址") {
                    copyProjectAddress()
                }
            Link("GPL-3.0 与开源来源", destination: Self.projectURL.appending(path: "blob/main/THIRD_PARTY_NOTICES.md"))
            Button("查看开源许可证") {
                PiliPresentation.present(.half) { PiliLicensesView() }
            }
        }
    }

    private var projectRow: some View {
        HStack {
            PiliLabel("项目地址", systemImage: "arrow.up.right.square")
            Spacer(minLength: 12)
            Text("SyIar/piliplus-re")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            PiliIcon(systemName: "arrow.up.right")
                .font(.cc.sm.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var projectAddressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .onEnded { _ in
                copyProjectAddress()
            }
            .exclusively(before: TapGesture().onEnded {
                openURL(Self.projectURL)
            })
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(version) (\(build))"
    }

    private func copyProjectAddress() {
        UIPasteboard.general.string = Self.projectURL.absoluteString
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

private struct PiliLicensesView: View {
    private var notices: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyLicenses", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "许可证见仓库中的 LICENSE 和 THIRD_PARTY_NOTICES.md。" }
        return text
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("开源许可证").ccText(font: .cc.lgBold, color: .cc.foreground)
                    Spacer()
                    Button { AppHelper.shared.dismissSheet() } label: {
                        PikaIcon(PikaIcon.Name.close).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("关闭")
                }
                Text(notices)
                    .ccText(font: .cc.sm, color: .cc.foreground)
                    .textSelection(.enabled)
            }
            .padding(24)
        }
        .background(Color.cc.background)
    }
}
