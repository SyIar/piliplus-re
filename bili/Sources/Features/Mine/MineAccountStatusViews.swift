import SwiftUI
import ChunUI

struct MineLoggedInHeaderView: View {
    let avatarURLString: String?
    let username: String
    let uidText: String

    var body: some View {
        HStack(spacing: 12) {
            AvatarRemoteImage(urlString: avatarURLString, pixelSize: 128) {
                PiliIcon(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(username)
                    .piliFont(.baseBold)
                Text(uidText)
                    .piliFont(.sm)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MineLoginPanelView: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let message: String
    let onQRCodeLogin: () -> Void
    let onSMSLogin: () -> Void
    let onWebLogin: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            PiliIcon(systemName: "person.crop.circle.badge.checkmark", size: 42)
                .piliFont(.lgBold)
                .foregroundStyle(appTintColor)

            Text(message.isEmpty ? "想让 App 端首页推荐更接近官方，优先用短信验证码；想稳定登录可用扫码。" : message)
                .piliFont(.base)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                LoginOptionButton(
                    title: "App 短信验证码登录",
                    subtitle: "更适合 App 端推荐，可能触发风控",
                    badge: "推荐",
                    systemImage: "message.badge",
                    tint: appTintColor,
                    isProminent: true,
                    action: onSMSLogin
                )

                LoginOptionButton(
                    title: "App 扫码登录",
                    subtitle: "更稳定；当前更适合配合网页端推荐",
                    badge: "稳定",
                    systemImage: "qrcode",
                    tint: .blue,
                    isProminent: false,
                    action: onQRCodeLogin
                )

                LoginOptionButton(
                    title: "网页登录",
                    subtitle: "备用登录方式，首页推荐个性化较弱",
                    badge: "备用",
                    systemImage: "globe",
                    tint: .secondary,
                    isProminent: false,
                    action: onWebLogin
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }
}

private struct LoginOptionButton: View {
    let title: String
    let subtitle: String
    let badge: String
    let systemImage: String
    let tint: Color
    let isProminent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                PiliIcon(systemName: systemImage)
                    .piliFont(.baseBold).fontWeight(.semibold)
                    .foregroundStyle(tint)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .piliFont(.base).fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Text(badge)
                            .piliFont(.sm).fontWeight(.semibold)
                            .foregroundStyle(isProminent ? .white : tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(isProminent ? tint : tint.opacity(0.12))
                            )
                    }

                    Text(subtitle)
                        .piliFont(.sm)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                PiliIcon(systemName: "chevron.right")
                    .piliFont(.sm).fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isProminent ? tint.opacity(0.10) : Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isProminent ? tint.opacity(0.45) : Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
