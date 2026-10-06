import SwiftUI
import ChunUI

private struct CommentContentOwnerMIDKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    var commentContentOwnerMID: Int? {
        get { self[CommentContentOwnerMIDKey.self] }
        set { self[CommentContentOwnerMIDKey.self] = newValue }
    }

}

struct CommentAvatar: View {
    let urlString: String?
    let owner: VideoOwner?
    let size: CGFloat

    init(urlString: String?, owner: VideoOwner? = nil, size: CGFloat) {
        self.urlString = urlString
        self.owner = owner
        self.size = size
    }

    var body: some View {
        Group {
            if let owner {
                VideoOwnerRouteLink(owner: owner) {
                    avatarImage
                }
                .accessibilityLabel("查看 \(owner.name) 的个人主页")
            } else {
                avatarImage
            }
        }
        .dynamicCommentHitArea(.control)
    }

    private var avatarImage: some View {
        let pixelSize = Int(size * 3)
        return AvatarRemoteImage(
            urlString: urlString,
            pixelSize: pixelSize,
            displayCachePolicy: .transient
        ) {
            PiliIcon(systemName: "person.crop.circle.fill", size: size * 0.9)
                .font(.system(size: size * 0.9))
                .foregroundStyle(.tertiary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct CommentAuthorIdentity: View {
    @Environment(\.commentContentOwnerMID) private var contentOwnerMID
    @Environment(\.appThemeTintColor) private var appTintColor

    let name: String
    let owner: VideoOwner?
    var member: CommentMember? = nil

    private var showsUPBadge: Bool {
        guard let contentOwnerMID, contentOwnerMID > 0 else { return false }
        return owner?.mid == contentOwnerMID
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(name)
                .appTypography(.commentAuthor, fallback: .subheadline.weight(.semibold))
                .lineLimit(1)

            if let level = member?.levelInfo?.currentLevel, (1...7).contains(level) {
                Text("LV\(level)").font(.cc.smBold)
                    .foregroundStyle(.secondary).accessibilityLabel("等级 \(level)")
            }
            if member?.isVIP == true {
                Text("大会员").font(.cc.sm).foregroundStyle(Color.cc.primary)
            }
            if let type = member?.verificationType {
                PiliIcon(systemName: "checkmark.seal.fill", size: 11).font(.cc.sm).foregroundStyle(type == 0 ? .orange : .blue)
                    .accessibilityLabel(type == 0 ? "个人认证" : "机构认证")
            }
            if showsUPBadge {
                BilibiliUPBadge(size: 16, color: appTintColor)
                    .alignmentGuide(.firstTextBaseline) { dimensions in
                        dimensions[.bottom] - 3
                    }
            }
        }
    }
}
