import SwiftUI
import ChunUI

struct FavoriteFolderRow: View {
    let folder: FavoriteFolder

    var body: some View {
        HStack(spacing: 10) {
            FavoriteFolderCover(folder: folder)
            FavoriteFolderInfo(folder: folder)

            Spacer(minLength: 8)

            PiliIcon(systemName: "chevron.right")
                .piliFont(.sm).fontWeight(.semibold)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}

private struct FavoriteFolderCover: View {
    let folder: FavoriteFolder

    var body: some View {
        if let cover = folder.cover?.normalizedBiliURL(),
           let url = URL(string: cover.biliCoverThumbnailURL(width: 240, height: 240)) {
            CachedRemoteImage(url: url, fallbackURL: URL(string: cover), targetPixelSize: 240) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                FavoriteFolderPlaceholder()
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .mediaShadow(.subtle)
        } else {
            FavoriteFolderPlaceholder()
        }
    }
}

private struct FavoriteFolderPlaceholder: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(appTintColor.opacity(0.12))
            .frame(width: 54, height: 54)
            .overlay {
                PiliIcon(systemName: "folder.fill")
                    .piliFont(.baseBold).fontWeight(.semibold)
                    .foregroundStyle(appTintColor)
            }
    }
}

private struct FavoriteFolderInfo: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let folder: FavoriteFolder

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(folder.displayTitle)
                .piliFont(.base).fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(2)

            HStack(spacing: 8) {
                PiliLabel("\(folder.mediaCount ?? 0) 个内容", systemImage: "play.rectangle.stack")
                if folder.isFavorited {
                    PiliLabel("已收藏当前视频", systemImage: "star.fill")
                        .foregroundStyle(appTintColor)
                }
            }
            .piliFont(.sm)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if let intro = folder.intro?.trimmingCharacters(in: .whitespacesAndNewlines),
               !intro.isEmpty {
                Text(intro)
                    .piliFont(.sm)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
