import SwiftUI
import ChunUI

struct LibraryEmptyRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        PiliLabel(title, systemImage: systemImage)
            .font(.cc.base)
            .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }
}
