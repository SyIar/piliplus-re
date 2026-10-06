import SwiftUI
import ChunUI

struct VideoDetailInfoMetadataRow: View {
    let metadataText: String
    let hasDescriptionContent: Bool
    let isExpanded: Bool
    let descriptionCopyText: String?
    let toggleExpansion: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(metadataText)
                .appTypography(.metadata, fallback: .caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hasDescriptionContent {
                Button(action: toggleExpansion) {
                    PiliIcon(systemName: isExpanded ? "chevron.up" : "chevron.down", size: 12)
                        .piliFont(.smBold)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(isExpanded ? "收起视频简介" : "展开视频简介")
            }
        }
        .frame(height: 24, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .commentCopyContextMenu(text: descriptionCopyText, title: "复制简介")
    }
}
