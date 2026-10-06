import SwiftUI
import ChunUI

struct DynamicOriginalAuthorIdentity: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let author: DynamicAuthor

    var body: some View {
        HStack(spacing: 6) {
            PiliIcon(systemName: "quote.opening")
                .font(.cc.sm.weight(.bold))
                .foregroundStyle(appTintColor)

            Text("转发自")
                .font(.cc.sm.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("@\(author.name ?? "Unknown")")
                .font(.cc.sm.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}
