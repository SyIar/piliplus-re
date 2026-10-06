import ChunUI
import PiliPlaybackCore
import SwiftUI

struct PiliOfflineLibraryView: View {
    @StateObject private var store = PiliOfflineStore.shared
    @State private var selection = Set<UUID>()
    @State private var editMode = EditMode.inactive
    @AppStorage("piliplus.offline.cellular") private var allowsCellular = false
    @AppStorage("piliplus.offline.groupCollections") private var groupsCollections = true

    private var groups: [(key: String, title: String, items: [OfflineDownloadItem])] {
        if !groupsCollections { return [("all", "全部下载", store.items)] }
        var order: [String] = [], values: [String: [OfflineDownloadItem]] = [:]
        for item in store.items {
            let key = item.collectionKey
            if values[key] == nil { order.append(key) }
            values[key, default: []].append(item)
        }
        return order.map { key in
            let items = values[key] ?? []
            return (key, items.first?.collectionTitle ?? items.first?.title ?? "合集", items)
        }
    }

    var body: some View {
        PiliSelectionList(selection: $selection) {
            if let error = store.storageError { Text(error).ccText(font: .cc.sm, color: .cc.mutedForeground) }
            Section {
                Toggle("允许蜂窝网络下载新任务", isOn: $allowsCellular)
                Toggle("按视频 / 合集分组", isOn: $groupsCollections)
                Text("已下载 \(ByteCountFormatter.string(fromByteCount: store.items.reduce(0) { $0 + $1.fileSize }, countStyle: .file))")
                    .ccText(font: .cc.sm, color: .cc.mutedForeground)
            }
            if store.items.isEmpty {
                VStack(spacing: 16) {
                    PikaIcon(PikaIcon.Name.save, size: 44)
                    Text("暂无离线内容").ccText(font: .cc.baseBold, color: .cc.foreground)
                    Text("在视频播放页选择“离线下载”").ccText(font: .cc.sm, color: .cc.mutedForeground)
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
        .navigationTitle("离线下载")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(editMode == .active ? "完成" : "选择") {
                    editMode = editMode == .active ? .inactive : .active
                    if editMode == .inactive { selection.removeAll() }
                }.disabled(store.items.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { AppHelper.shared.dismissSheet() } label: { PikaIcon(PikaIcon.Name.close) }
                    .accessibilityLabel("关闭")
            }
            if editMode == .active {
                ToolbarItem(placement: .bottomBar) {
                    CCNeoButton("删除所选 \(selection.count) 项", variant: .danger, disabled: selection.isEmpty) {
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
        HStack {
            switch item.state {
            case .queued, .preparing, .downloading, .finalizing:
                CCNeoButton("暂停", variant: .secondary) { store.pause(item.id) }
            case .paused, .failed:
                CCNeoButton("继续", variant: .secondary) { store.resume(item.id) }
            case .completed:
                if let url = try? PiliOfflineStorage.playbackURL(item) {
                    ShareLink(item: url) {
                        Label { Text(item.effectiveMediaKind == .audio ? "导出音频" : "导出视频") } icon: { PikaIcon(PikaIcon.Name.file) }
                    }.buttonStyle(.glass)
                }
                if (item.effectiveMediaKind == .video && !item.hasDanmaku) || item.hasSubtitles != true {
                    CCNeoButton(item.effectiveMediaKind == .audio ? "下载字幕" : "下载弹幕与字幕", variant: .ghost) { store.cacheDanmaku(item.id) }
                }
            }
            Spacer(minLength: 0)
            Button { confirmDelete([item.id]) } label: { PikaIcon(PikaIcon.Name.trash) }
                .buttonStyle(.borderless).accessibilityLabel("删除下载")
        }
    }

    private func confirmDelete(_ ids: Set<UUID>) {
        CCAlertCenter.shared.present(title: "删除 \(ids.count) 个下载？", message: "媒体文件和对应离线数据将从本机移除。", actions: [
            CCAlertAction(title: "取消", role: .secondary),
            CCAlertAction(title: "删除", role: .destructive) {
                ids.forEach(store.remove)
                selection.subtract(ids)
            },
        ])
    }
}

extension OfflineDownloadState {
    var piliTitle: String {
        switch self {
        case .queued: "排队中"
        case .preparing: "获取下载地址"
        case .downloading: "下载中"
        case .paused: "已暂停"
        case .finalizing: "整理媒体文件"
        case .completed: "已完成"
        case .failed: "下载失败"
        }
    }
}
