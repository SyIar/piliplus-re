import ChunUI
import PiliPlaybackCore
import SwiftUI

struct PiliOfflineLibraryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var store = PiliOfflineStore.shared
    @State private var selection = Set<UUID>()
    @State private var editMode = EditMode.inactive
    @AppStorage("piliplus.offline.cellular") private var allowsCellular = false
    @AppStorage("piliplus.offline.groupCollections") private var groupsCollections = true

    private var groups: [(key: String, title: String, items: [OfflineDownloadItem])] {
        if !groupsCollections { return [("all", "\u{5168}\u{90e8}\u{4e0b}\u{8f7d}", store.items)] }
        var order: [String] = [], values: [String: [OfflineDownloadItem]] = [:]
        for item in store.items {
            let key = item.collectionKey
            if values[key] == nil { order.append(key) }
            values[key, default: []].append(item)
        }
        return order.map { key in
            let items = values[key] ?? []
            return (key, items.first?.collectionTitle ?? items.first?.title ?? "\u{5408}\u{96c6}", items)
        }
    }

    var body: some View {
        PiliSelectionList(selection: $selection) {
            if let error = store.storageError { Text(error).ccText(font: .cc.sm, color: .cc.mutedForeground) }
            Section {
                Toggle("\u{5141}\u{8bb8}\u{8702}\u{7a9d}\u{7f51}\u{7edc}\u{4e0b}\u{8f7d}\u{65b0}\u{4efb}\u{52a1}", isOn: $allowsCellular)
                Toggle("\u{6309}\u{89c6}\u{9891} / \u{5408}\u{96c6}\u{5206}\u{7ec4}", isOn: $groupsCollections)
                Text("\u{5df2}\u{4e0b}\u{8f7d} \(ByteCountFormatter.string(fromByteCount: store.items.reduce(0) { $0 + $1.fileSize }, countStyle: .file))")
                    .ccText(font: .cc.sm, color: .cc.mutedForeground)
            }
            if store.items.isEmpty {
                VStack(spacing: 16) {
                    PikaIcon(PikaIcon.Name.save, size: 44)
                    Text("\u{6682}\u{65e0}\u{79bb}\u{7ebf}\u{5185}\u{5bb9}").ccText(font: .cc.baseBold, color: .cc.foreground)
                    Text("\u{5728}\u{89c6}\u{9891}\u{64ad}\u{653e}\u{9875}\u{9009}\u{62e9}“\u{79bb}\u{7ebf}\u{4e0b}\u{8f7d}”").ccText(font: .cc.sm, color: .cc.mutedForeground)
                }.frame(maxWidth: .infinity).padding(.vertical, 36)
            } else {
                ForEach(groups, id: \.key) { group in
                    Section(group.title) {
                    ForEach(group.items) { item in
                    VStack(alignment: .leading, spacing: 12) {
                        if let url = try? PiliOfflineStorage.playbackURL(item), editMode != .active {
                            NavigationLink {
                                PiliOfflinePlayerScreen(item: item, url: url)
                            } label: { itemTitle(item) }
                        } else { itemTitle(item) }
                        if item.state == .downloading {
                            if let progress = item.progress { ProgressView(value: progress) }
                            else { ProgressView() }
                        }
                        if let error = item.errorMessage { Text(error).ccText(font: .cc.sm, color: .cc.mutedForeground) }
                        if let error = item.extrasError { Text(error).ccText(font: .cc.sm, color: .cc.mutedForeground) }
                        if editMode != .active { controls(item) }
                    }
                    .padding(.vertical, 8)
                    .tag(item.id)
                    }
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("\u{79bb}\u{7ebf}\u{4e0b}\u{8f7d}")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(editMode == .active ? "\u{5b8c}\u{6210}" : "\u{9009}\u{62e9}") {
                    editMode = editMode == .active ? .inactive : .active
                    if editMode == .inactive { selection.removeAll() }
                }.disabled(store.items.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { AppHelper.shared.dismissSheet() } label: { PikaIcon(PikaIcon.Name.close) }
                    .accessibilityLabel("\u{5173}\u{95ed}")
            }
            if editMode == .active {
                ToolbarItem(placement: .bottomBar) {
                    CCNeoButton("\u{5220}\u{9664}\u{6240}\u{9009} \(selection.count) \u{9879}", variant: .danger, disabled: selection.isEmpty) {
                        confirmDelete(selection)
                    }
                }
            }
        }
    }

    private func itemTitle(_ item: OfflineDownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title).ccText(font: .cc.baseBold, color: .cc.foreground).lineLimit(3)
            Text("\(item.qualityTitle) · \(item.state.piliTitle)").ccText(font: .cc.sm, color: .cc.mutedForeground)
        }
    }

    @ViewBuilder
    private func controls(_ item: OfflineDownloadItem) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            switch item.state {
            case .queued, .preparing, .downloading, .finalizing:
                CCNeoButton("\u{6682}\u{505c}", variant: .secondary) { store.pause(item.id) }
            case .paused, .failed:
                CCNeoButton("\u{7ee7}\u{7eed}", variant: .secondary) { store.resume(item.id) }
            case .completed:
                if let url = try? PiliOfflineStorage.playbackURL(item) {
                    ShareLink(item: url) {
                        Label { Text(item.effectiveMediaKind == .audio ? "\u{5bfc}\u{51fa}\u{97f3}\u{9891}" : "\u{5bfc}\u{51fa}\u{89c6}\u{9891}") } icon: { PikaIcon(PikaIcon.Name.file) }
                    }.buttonStyle(.glass)
                }
                if (item.effectiveMediaKind == .video && !item.hasDanmaku) || item.hasSubtitles != true {
                    CCNeoButton(item.effectiveMediaKind == .audio ? "\u{4e0b}\u{8f7d}\u{5b57}\u{5e55}" : "\u{4e0b}\u{8f7d}\u{5f39}\u{5e55}\u{4e0e}\u{5b57}\u{5e55}", variant: .ghost) { store.cacheDanmaku(item.id) }
                }
            }
            Spacer(minLength: 0)
            Button { confirmDelete([item.id]) } label: { PikaIcon(PikaIcon.Name.trash) }
                .buttonStyle(.borderless).accessibilityLabel("\u{5220}\u{9664}\u{4e0b}\u{8f7d}")
        }
    }

    private func confirmDelete(_ ids: Set<UUID>) {
        PiliAlertSession.present(title: "\u{5220}\u{9664} \(ids.count) \u{4e2a}\u{4e0b}\u{8f7d}？", message: "\u{5a92}\u{4f53}\u{6587}\u{4ef6}\u{548c}\u{5bf9}\u{5e94}\u{79bb}\u{7ebf}\u{6570}\u{636e}\u{5c06}\u{4ece}\u{672c}\u{673a}\u{79fb}\u{9664}。", actions: [
            PiliAlertButton("\u{53d6}\u{6d88}", role: .cancel),
            PiliAlertButton("\u{5220}\u{9664}", role: .destructive) {
                ids.forEach(store.remove)
                selection.subtract(ids)
            },
        ])
    }
}

extension OfflineDownloadState {
    var piliTitle: String {
        switch self {
        case .queued: "\u{6392}\u{961f}\u{4e2d}"
        case .preparing: "\u{83b7}\u{53d6}\u{4e0b}\u{8f7d}\u{5730}\u{5740}"
        case .downloading: "\u{4e0b}\u{8f7d}\u{4e2d}"
        case .paused: "\u{5df2}\u{6682}\u{505c}"
        case .finalizing: "\u{6574}\u{7406}\u{5a92}\u{4f53}\u{6587}\u{4ef6}"
        case .completed: "\u{5df2}\u{5b8c}\u{6210}"
        case .failed: "\u{4e0b}\u{8f7d}\u{5931}\u{8d25}"
        }
    }
}
