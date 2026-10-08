import SwiftUI

struct MineDashboardIdentity: View {
    let user: NavUserInfo?
    let isLoggedIn: Bool
    var body: some View {
        HStack(spacing: 18) {
            AvatarRemoteImage(urlString: user?.face, pixelSize: 192) {
                PiliIcon(systemName: "person.crop.circle.fill", size: 60).foregroundStyle(.secondary)
            }.frame(width: 72, height: 72).clipShape(Circle())
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(isLoggedIn ? (user?.uname ?? "\u{5df2}\u{767b}\u{5f55}") : "\u{767b}\u{5f55}\u{8d26}\u{53f7}")
                        .font(.title3.weight(.semibold)).lineLimit(2)
                    if let level = user?.levelInfo?.level {
                        Text("LV\(level)").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    }
                }
                if isLoggedIn {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { coins; experience }
                        VStack(alignment: .leading, spacing: 4) { coins; experience }
                    }.font(.caption).foregroundStyle(.secondary)
                    if let current = user?.levelInfo?.current, let next = user?.levelInfo?.next, next > 0 {
                        ProgressView(value: min(1, Double(current) / Double(next)))
                            .tint(.secondary).accessibilityLabel("\u{7b49}\u{7ea7}\u{7ecf}\u{9a8c}")
                    }
                } else { Text("\u{540c}\u{6b65}\u{6536}\u{85cf}、\u{5173}\u{6ce8}\u{4e0e}\u{89c2}\u{770b}\u{8bb0}\u{5f55}").font(.subheadline).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 8).contentShape(Rectangle())
    }
    private var coins: some View {
        Text("\u{786c}\u{5e01} \(user?.money.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—")")
    }
    private var experience: some View {
        Text("\u{7ecf}\u{9a8c} \(user?.levelInfo?.current.map(String.init) ?? "—") / \(user?.levelInfo?.next.map(String.init) ?? "—")")
    }
}

struct MineDashboardStat: View {
    let title: String
    let count: Int?
    var body: some View {
        VStack(spacing: 7) {
            Text(count.map(String.init) ?? "—").font(.title3.weight(.semibold)).monospacedDigit()
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 60).contentShape(Rectangle())
    }
}

struct MineDashboardShortcut: View {
    let title: String
    let icon: String
    var body: some View {
        VStack(spacing: 10) {
            PiliIcon(systemName: icon, size: 24).frame(height: 28)
            Text(title).font(.caption).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 64).contentShape(Rectangle())
    }
}

struct MineDashboardFolder: View {
    let folder: FavoriteFolder
    var api: BiliAPIClient? = nil
    @State private var loadedMetadata: FavoriteFolder?
    private var displayFolder: FavoriteFolder { loadedMetadata ?? folder }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.secondary.opacity(0.08)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    CachedRemoteImage(url: displayFolder.cover.flatMap { URL(string: $0.normalizedBiliURL()) }, targetPixelSize: 720) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { PiliIcon(systemName: "folder", size: 28).foregroundStyle(.secondary) }
                }.clipShape(RoundedRectangle(cornerRadius: 12))
            Text(folder.displayTitle).font(.subheadline).lineLimit(2)
            Text("\u{5171} \(folder.mediaCount ?? 0) \u{6761}\u{89c6}\u{9891} · \(folder.isPiliPublic ? "\u{516c}\u{5f00}" : "\u{79c1}\u{5bc6}")")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .topLeading).contentShape(Rectangle())
        .task(id: folder.id) {
            guard loadedMetadata == nil, folder.cover?.isEmpty != false, let api else { return }
            let identity = PiliAccountIdentity(api.requestSnapshot(purpose: .interaction))
            guard identity.mid > 0 else { return }
            let metadata = try? await api.fetchPiliFavoriteFolder(id: folder.id)
            guard !Task.isCancelled, identity.matches(api.requestSnapshot(purpose: .interaction)),
                  metadata?.id == folder.id else { return }
            loadedMetadata = metadata
        }
    }
}
