import SwiftUI

/// Equal flexible columns, with an explicit hit area and scalable captions.
struct VideoDetailActionLabel: View {
    let title: String
    let systemImage: String
    var isBusy = false

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if isBusy { ProgressView().controlSize(.small) }
                else { PiliIcon(systemName: systemImage, size: 22) }
            }
            .frame(width: 24, height: 24)
            Text(title)
                .font(.caption)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
