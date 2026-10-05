import ChunUI
import SwiftUI

struct PiliWatchLaterToolsView: View {
    @ObservedObject var viewModel: MineViewModel
    @State private var selected = Set<Int>()
    @State private var folders: [FavoriteFolder] = []
    @State private var targetMode: TargetMode?
    @State private var downloadRequest: PiliBatchDownloadRequest?
    @State private var loadingTargets = false
    @State private var confirmRemove = false
    @State private var confirmCleanup = false
    @State private var cleanup: WatchLaterCleanup = .invalid
    @State private var errorMessage: String?
    private enum TargetMode: String, Identifiable { case copy, move; var id: String { rawValue } }

    private var busy: Bool { viewModel.isMutatingWatchLater || loadingTargets }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button("全选已加载") {
                            selected = Set(viewModel.accountWatchLater.compactMap(\.aid).filter { $0 > 0 }.prefix(100))
                        }
                        Spacer()
                        Button("取消选择") { selected = [] }
                    }
                    Text("已选择 \(selected.count) 个视频，每批最多 100 个")
                        .ccText(font: .cc.sm, color: .cc.mutedForeground)
                    Text("使用当前页面的筛选结果；清理操作适用于整个稍后再看列表。")
                        .ccText(font: .cc.sm, color: .cc.mutedForeground)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(Color.cc.destructive) }
                Section {
                    ForEach(viewModel.accountWatchLater) { item in
                        if let aid = item.aid, aid > 0 {
                            Button { toggle(aid) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selected.contains(aid) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(Color.cc.primary)
                                    LibraryVideoRow(item: item, timestampTitle: "添加时间")
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                    if viewModel.watchLaterState.isLoading || viewModel.watchLaterLoadMoreState.isLoading {
                        ProgressView("加载稍后再看")
                    } else if case .failed(let message) = viewModel.watchLaterLoadMoreState {
                        Text(message).foregroundStyle(Color.cc.destructive)
                        Button("重试加载") { Task { await viewModel.loadMoreWatchLater() } }
                    } else if case .failed(let message) = viewModel.watchLaterState {
                        Text(message).foregroundStyle(Color.cc.destructive)
                        Button("重新加载") { Task { await viewModel.refreshWatchLater(applyingFilter: false) } }
                    } else if viewModel.watchLaterHasMore {
                        Button("加载更多") { Task { await viewModel.loadMoreWatchLater() } }
                    } else if viewModel.accountWatchLater.isEmpty { Text("没有匹配的视频") }
                }
            }
            .disabled(busy)
            .navigationTitle("管理稍后再看")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { AppHelper.shared.dismissSheet() }.disabled(busy)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("缓存所选视频") { showDownload(all: false) }.disabled(selected.isEmpty)
                        Button("缓存全部筛选结果") { showDownload(all: true) }
                        Divider()
                        Button("复制到收藏夹") { showTargets(.copy) }.disabled(selected.isEmpty)
                        Button("移入收藏夹") { showTargets(.move) }.disabled(selected.isEmpty)
                        Button("移除所选视频", role: .destructive) { confirmRemove = true }.disabled(selected.isEmpty)
                        Divider()
                        Button("移除已看完的视频", role: .destructive) { showCleanup(.viewed) }
                        Button("移除失效的视频", role: .destructive) { showCleanup(.invalid) }
                        Button("清空全部", role: .destructive) { showCleanup(.all) }
                    } label: { PikaIcon(PikaIcon.Name.more).frame(width: 44, height: 44) }
                    .disabled(busy || viewModel.watchLaterState.isLoading)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selected.isEmpty {
                    HStack {
                        Button("缓存") { showDownload(all: false) }
                        Button("复制") { showTargets(.copy) }
                        Button("移入收藏夹") { showTargets(.move) }
                        Spacer()
                        Button("移除", role: .destructive) { confirmRemove = true }
                    }.buttonStyle(.glass).padding(16).background(.ultraThinMaterial).disabled(busy)
                }
            }
            .refreshable { await viewModel.refreshWatchLater(applyingFilter: false) }
            .onChange(of: viewModel.watchLaterGeneration) { _, _ in
                selected = []; folders = []; targetMode = nil; downloadRequest = nil; confirmRemove = false; confirmCleanup = false
            }
            .alert("移除所选的 \(selected.count) 个视频？", isPresented: $confirmRemove) {
                Button("取消", role: .cancel) {}
                Button("移除", role: .destructive) { mutate() }
            } message: { Text("从稍后再看列表中移除这些记录。") }
            .alert(cleanupTitle, isPresented: $confirmCleanup) {
                Button("取消", role: .cancel) {}
                Button("确认", role: .destructive) {
                    let mode = cleanup
                    Task {
                        do { try await viewModel.cleanWatchLater(mode); errorMessage = nil }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
            } message: { Text("操作会同步到当前历史账号，不能撤销。") }
            .sheet(item: $targetMode) { mode in
                NavigationStack {
                    List {
                        ForEach(folders) { folder in
                            Button(folder.displayTitle) {
                                targetMode = nil
                                mutate(target: folder.id, move: mode == .move)
                            }
                        }
                        if folders.isEmpty { Text("没有收藏夹，请先为当前历史账号新建收藏夹") }
                    }
                    .navigationTitle(mode == .copy ? "复制到收藏夹" : "移入收藏夹")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { targetMode = nil } } }
                }
            }
            .sheet(item: $downloadRequest) { request in
                PiliBatchDownloadSheet(api: viewModel.offlineDownloadAPI, request: request)
            }
        }
    }
    private var cleanupTitle: String {
        switch cleanup {
        case .viewed: "移除所有已看完的视频？"
        case .invalid: "移除所有失效的视频？"
        case .all: "清空全部稍后再看？"
        }
    }
    private func toggle(_ aid: Int) {
        if selected.contains(aid) { selected.remove(aid) }
        else if selected.count < 100 { selected.insert(aid) }
        else { errorMessage = "每批最多选择 100 个视频" }
    }
    private func showCleanup(_ mode: WatchLaterCleanup) { cleanup = mode; confirmCleanup = true }
    private func showDownload(all: Bool) {
        do { downloadRequest = try viewModel.watchLaterDownloadRequest(selected: all ? nil : selected) }
        catch { errorMessage = error.localizedDescription }
    }
    private func showTargets(_ mode: TargetMode) {
        guard !busy, !selected.isEmpty else { return }
        loadingTargets = true; errorMessage = nil
        Task {
            defer { loadingTargets = false }
            do { folders = try await viewModel.watchLaterDestinationFolders(); targetMode = mode }
            catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }
    private func mutate(target: Int? = nil, move: Bool = false) {
        let aids = Array(selected)
        Task {
            do {
                try await viewModel.batchWatchLater(aids: aids, targetFolder: target, move: move)
                selected = []; errorMessage = nil
                CCToastCenter.shared.show(.success, "稍后再看已更新")
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
