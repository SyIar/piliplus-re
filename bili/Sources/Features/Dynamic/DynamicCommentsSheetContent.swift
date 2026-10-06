import SwiftUI

struct DynamicCommentsSheetContent: View {
    @ObservedObject var viewModel: DynamicCommentsViewModel
    let highlightedCommentID: Int?
    let selectSort: @MainActor @Sendable (CommentSort) -> Void
    let showReplies: (Comment) -> Void
    var dividerHorizontalPadding: CGFloat = 14
    var replyToComment: ((Comment) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DynamicCommentsHeader(
                replyCount: viewModel.displayedReplyCount,
                selectedSort: Binding(
                    get: { viewModel.selectedSort },
                    // Keep the MainActor call explicit. Passing the isolated
                    // function directly triggers a Swift 6.3 IRGen thunk crash.
                    set: { sort in selectSort(sort) }
                )
            )
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 6)

            DynamicCommentsListContent(
                viewModel: viewModel,
                highlightedCommentID: highlightedCommentID,
                showReplies: showReplies,
                dividerHorizontalPadding: dividerHorizontalPadding,
                replyToComment: replyToComment
            )
        }
    }
}
