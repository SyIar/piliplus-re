import SwiftUI
import ChunUI

struct VideoDetailNoticeLabel: View {
    let message: String
    let systemImage: String

    var body: some View {
        PiliLabel(message, systemImage: systemImage)
            .font(.cc.sm)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
