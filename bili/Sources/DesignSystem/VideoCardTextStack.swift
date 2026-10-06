import SwiftUI
import ChunUI

private struct VideoCardHasTrailingMenuKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var videoCardHasTrailingMenu: Bool {
        get { self[VideoCardHasTrailingMenuKey.self] }
        set { self[VideoCardHasTrailingMenuKey.self] = newValue }
    }
}

struct VideoCardTextStack: View {
    @Environment(\.videoCardHasTrailingMenu) private var hasTrailingMenu
    let display: VideoCardDisplayModel
    let showsPublishTimeInAuthorRow: Bool
    let showsAuthorIdentity: Bool
    let usesGenericAuthorIcon: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleLabel
            authorRow.padding(.trailing, hasTrailingMenu ? 26 : 0)
        }
    }

    private var titleLabel: some View {
        StableVideoTitleText(display.title, style: .compactCard)
            .frame(minHeight: 36, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var authorRow: some View {
        HStack(spacing: 4) {
            if showsAuthorIdentity {
                authorIdentityIcon

                Text(display.authorName)
                    .appTypography(.compactAuthor, fallback: .caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if showsPublishTimeInAuthorRow {
                if showsAuthorIdentity {
                    Spacer(minLength: 6)
                }

                Text(display.publishTimeText)
                    .appTypography(.tertiaryMetadata, fallback: .caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var authorIdentityIcon: some View {
        if usesGenericAuthorIcon {
            BilibiliUPBadge(size: 14)
        } else {
            AvatarRemoteImage(urlString: display.avatarURLString, pixelSize: 48) {
                PiliIcon(systemName: "person.crop.circle.fill", size: 13)
                    .piliFont(.sm)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 14, height: 14)
            .clipShape(Circle())
            .mediaShadow(.subtle)
        }
    }
}
