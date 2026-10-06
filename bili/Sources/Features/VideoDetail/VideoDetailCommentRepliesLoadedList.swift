import SwiftUI

struct CommentRepliesLoadedList: View {
    let snapshot: VideoDetailCommentThreadRepliesSnapshot
    let rootComment: Comment
    let loadMoreReplies: (Comment) async -> Void
    let showDialog: (Comment) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            PiliCommentTreeRows(rootID: rootComment.id, items: snapshot.replyDisplays, parentID: { $0.reply.parentID }) { replyDisplay in
                CommentReplyDetailRow(
                    item: replyDisplay,
                    showDialog: replyDisplay.canShowDialog ? {
                        showDialog(replyDisplay.reply)
                    } : nil
                )
                .padding(.horizontal, 16)
            }

            CommentRepliesFooter(
                snapshot: snapshot,
                rootComment: rootComment,
                loadMoreReplies: loadMoreReplies
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}
