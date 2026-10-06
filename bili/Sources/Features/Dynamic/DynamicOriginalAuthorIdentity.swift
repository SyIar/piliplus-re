import SwiftUI
import ChunUI

struct DynamicOriginalAuthorIdentity: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let author: DynamicAuthor

    var body: some View {
        HStack(spacing: 6) {
            PiliIcon(systemName: "quote.opening")
                .piliFont(.sm).fontWeight(.bold)
                .foregroundStyle(appTintColor)

            Text("转发自")
                .piliFont(.sm).fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("@\(author.name ?? "Unknown")")
                .piliFont(.sm).fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}
