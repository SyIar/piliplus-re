import SwiftUI
import ChunUI
import UIKit

struct QRCodeLoginContent: View {
    let state: QRCodeLoginState
    let refresh: () -> Void

    var body: some View {
        switch state {
        case .idle, .loading:
            QRCodeLoginLoadingState(message: state.message)

        case .waiting(let info, _), .scanned(let info, _):
            QRCodeLoginActiveState(
                state: state,
                info: info,
                refresh: refresh
            )

        case .expired(let message):
            QRCodeLoginRetryState(
                systemImage: "qrcode",
                title: "二维码已过期",
                message: message,
                refresh: refresh
            )

        case .failed(let message):
            QRCodeLoginRetryState(
                systemImage: "exclamationmark.triangle",
                title: "二维码登录失败",
                message: message,
                refresh: refresh
            )

        case .succeeded(let message):
            QRCodeLoginSucceededState(message: message)
        }
    }
}

private struct QRCodeLoginLoadingState: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(message)
                .piliFont(.base)
                .foregroundStyle(.secondary)
        }
    }
}

private struct QRCodeLoginActiveState: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let state: QRCodeLoginState
    let info: QRCodeLoginInfo
    let refresh: () -> Void

    @State private var copiedURL = false

    private var statusIcon: String {
        if case .scanned = state {
            return "checkmark.circle"
        }
        return "qrcode.viewfinder"
    }

    private var statusColor: Color {
        if case .scanned = state {
            return appTintColor
        }
        return .secondary
    }

    private var bilibiliOpenURL: URL? {
        var components = URLComponents()
        components.scheme = "bilibili"
        components.host = "browser"
        components.queryItems = [URLQueryItem(name: "url", value: info.url)]
        return components.url
    }

    var body: some View {
        VStack(spacing: 18) {
            QRCodeImage(value: info.url)
                .frame(width: 236, height: 236)
                .padding(14)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            PiliLabel(state.message, systemImage: statusIcon)
                .piliFont(.base).fontWeight(.semibold)
                .foregroundStyle(statusColor)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button {
                    if let bilibiliOpenURL {
                        UIApplication.shared.open(bilibiliOpenURL)
                    }
                } label: {
                    PiliLabel("用 B 站打开", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.glassProminent)
                .tint(Color.cc.primary)

                Button(action: refresh) {
                    PiliLabel("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
            }

            Button {
                UIPasteboard.general.string = info.url
                copiedURL = true
            } label: {
                PiliLabel(copiedURL ? "已复制链接" : "复制登录链接", systemImage: copiedURL ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.glass)
        }
    }
}

private struct QRCodeLoginRetryState: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let systemImage: String
    let title: String
    let message: String
    let refresh: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            PiliIcon(systemName: systemImage, size: 48)
                .piliFont(.lgBold)
                .foregroundStyle(.secondary)

            Text(title)
                .piliFont(.baseBold)

            Text(message)
                .piliFont(.base)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: refresh) {
                PiliLabel("重新生成", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.glassProminent)
            .tint(appTintColor)
        }
    }
}

private struct QRCodeLoginSucceededState: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            PiliIcon(systemName: "checkmark.circle.fill", size: 54)
                .piliFont(.lgBold)
                .foregroundStyle(Color.cc.success)
            Text(message)
                .piliFont(.baseBold)
        }
    }
}
