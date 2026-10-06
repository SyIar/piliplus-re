import SwiftUI
import ChunUI

struct VideoFeedStoryHeader: View {
    let display: VideoCardDisplayModel

    var body: some View {
        HStack(spacing: 9) {
            AvatarRemoteImage(urlString: display.avatarURLString, pixelSize: 64) {
                PiliIcon(systemName: "person.crop.circle.fill", size: 26)
                    .font(.cc.lg)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .mediaShadow(.subtle)

            Text(display.authorName)
                .appTypography(.author)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 10)

            Text(display.publishTimeText)
                .font(.cc.sm)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 2)
    }
}
