import SwiftUI
import ChunUI

struct CommentsSectionHeader: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    @ObservedObject var store: VideoDetailCommentsRenderStore
    let style: CommentSectionStyle
    let selectCommentSort: (CommentSort) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("评论")
                .piliFont(.baseBold)

            if let count = store.replyCountText {
                Text(count)
                    .piliFont(.sm).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(CommentSort.allCases) { sort in
                    Button {
                        selectCommentSort(sort)
                    } label: {
                        Text(sort.title)
                            .piliFont(.sm).fontWeight(.semibold)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(store.selectedSort == sort ? appTintColor.opacity(0.14) : Color.clear)
                            .foregroundStyle(store.selectedSort == sort ? appTintColor : .secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, style.horizontalPadding)
    }
}
