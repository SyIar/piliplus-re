import SwiftUI
import ChunUI

struct BiliContentStateSurface<Actions: View>: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    let actions: Actions

    init(
        title: String,
        message: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            PiliIcon(systemName: systemImage, size: 28)
                .font(.cc.lgBold)
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(Color(.tertiarySystemFill), in: Circle())

            VStack(spacing: 5) {
                Text(title)
                    .font(.cc.baseBold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.cc.base)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actions
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .piliGlassCard()
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 0.6)
        }
        .padding(.horizontal, 18)
        .accessibilityElement(children: .combine)
    }
}
