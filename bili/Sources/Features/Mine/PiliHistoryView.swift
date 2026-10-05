import ChunUI
import SwiftUI

struct PiliHistoryView: View {
    @StateObject private var model: PiliHistoryModel
    @ObservedObject private var session: SessionStore
    @ObservedObject private var library: LibraryStore
    @State private var confirmation: Confirmation?
    @State private var confirmsAction = false
    private struct Confirmation {
        let title: String
        let message: String
        let action: PiliHistoryMutation
    }
    init(api: BiliAPIClient) {
        _model = StateObject(wrappedValue: PiliHistoryModel(api: api))
        _session = ObservedObject(wrappedValue: api.sessionStore)
        _library = ObservedObject(wrappedValue: api.libraryStore)
    }
    var body: some View {
        List {
            if session.isLoggedIn {
                Section {
                    Picker("历史分类", selection: $model.selectedType) {
                        ForEach(model.tabs) { Text($0.title).tag($0.id) }
                    }.disabled(!model.keyword.isEmpty)
                    if !model.keyword.isEmpty {
                        Text("搜索范围：全部历史分类").ccText(font: .cc.sm, color: .cc.mutedForeground)
                    }
                    if model.paused == true {
                        Label("已暂停云端观看记录", systemImage: "pause.circle")
                            .ccText(font: .cc.sm, color: .cc.mutedForeground)
                    }
                    if model.isSelecting {
                        HStack {
                            Button("全选已加载") { model.selectLoaded() }
                            Spacer()
                            Button("取消选择") { model.selection = [] }
                        }
                        Text("已选择 \(model.selection.count) 条，每批最多 100 条")
                            .ccText(font: .cc.sm, color: .cc.mutedForeground)
                    }
                }
                if let error = model.errorMessage {
                    Section {
                        Text(error).foregroundStyle(Color.cc.destructive)
                        Button("重新加载") { Task { await model.activateAccount() } }
                    }
                }
                Section {
                    ForEach(model.items) { item in
                        Group {
                            if model.isSelecting {
                                Button { model.toggle(item) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: model.selection.contains(item.deletionKey ?? "") ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(Color.cc.primary)
                                        PiliHistoryRow(item: item)
                                    }
                                }.buttonStyle(.plain).disabled(item.deletionKey == nil)
                            } else if let video = item.video {
                                VideoRouteLink(video) { PiliHistoryRow(item: item) }
                            } else if let url = item.destinationURL {
                                AppLinkButton(url: url) { PiliHistoryRow(item: item) }
                            } else { PiliHistoryRow(item: item) }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if let key = item.deletionKey {
                                Button("删除", role: .destructive) { confirmDelete([key]) }
                            }
                        }
                        .task {
                            if model.items.last?.id == item.id { await model.load() }
                        }
                    }
                    if model.isLoading { ProgressView("加载历史记录") }
                    else if model.hasMore { Button("加载更多") { Task { await model.load() } } }
                    else if model.items.isEmpty { ContentUnavailableView("暂无历史记录", systemImage: "clock") }
                }
            } else { ContentUnavailableView("登录后查看观看历史", systemImage: "clock") }
        }
        .disabled(model.isMutating)
        .nativeTopScrollEdgeEffect()
        .navigationTitle("观看历史")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.keyword, prompt: "搜索观看历史")
        .onSubmit(of: .search) { Task { await model.load(reset: true) } }
        .onChange(of: model.selectedType) { _, _ in Task { await model.load(reset: true) } }
        .onChange(of: model.keyword) { _, text in if text.isEmpty { Task { await model.load(reset: true) } } }
        .task(id: "\(session.historyAccountCredentialVersion)-\(library.multiAccountExperimentEnabled)") {
            confirmation = nil; confirmsAction = false
            await model.activateAccount()
        }
        .refreshable { await model.activateAccount() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(model.isSelecting ? "退出多选" : "批量管理") { model.isSelecting.toggle(); model.selection = [] }
                    Button("选择已加载的已看完记录") { model.selectLoaded(finishedOnly: true) }
                    Divider()
                    if let paused = model.paused {
                        Button(paused ? "恢复云端观看记录" : "暂停云端观看记录") {
                            confirmation = Confirmation(title: paused ? "恢复云端观看记录？" : "暂停云端观看记录？",
                                message: "设置同步到当前历史账号；本机播放进度仍会保留。", action: .pause(!paused))
                            confirmsAction = true
                        }
                    } else { Button("读取记录暂停状态") { Task { await model.loadPauseStatus() } } }
                    Button("清空全部历史", role: .destructive) {
                        confirmation = Confirmation(title: "清空全部历史记录？", message: "将删除当前历史账号所有分类的云端记录，包括未加载的记录，不能撤销。", action: .clear)
                        confirmsAction = true
                    }
                } label: { PikaIcon(PikaIcon.Name.more).frame(width: 44, height: 44) }
                .disabled(!session.isLoggedIn || model.isMutating || model.isLoadingPause)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.isSelecting && !model.selection.isEmpty {
                Button("删除所选的 \(model.selection.count) 条记录", role: .destructive) { confirmDelete(Array(model.selection)) }
                    .buttonStyle(.glass).padding(16).frame(maxWidth: .infinity).background(.ultraThinMaterial)
                    .disabled(model.isMutating || model.isLoadingPause)
            }
        }
        .alert(confirmation?.title ?? "确认操作", isPresented: $confirmsAction) {
            Button("取消", role: .cancel) { confirmation = nil }
            Button("确认", role: .destructive) {
                if let action = confirmation?.action { Task { await model.mutate(action) } }
            }
        } message: { Text(confirmation?.message ?? "") }
    }
    private func confirmDelete(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        confirmation = Confirmation(title: "删除这 \(keys.count) 条历史记录？", message: "删除会同步到当前历史账号，不能撤销。", action: .delete(keys: keys))
        confirmsAction = true
    }
}

private struct PiliHistoryRow: View {
    let item: PiliHistoryRecord
    var body: some View {
        HStack(spacing: 12) {
            CachedRemoteImage(url: item.cover.flatMap(URL.init(string:)), targetPixelSize: 288) { image in
                image.resizable().scaledToFill()
            } placeholder: { Color.cc.muted.opacity(0.25) }
                .frame(width: 100, height: 64).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).ccText(font: .cc.base, color: .cc.foreground).lineLimit(2)
                Text([item.kindTitle, item.author].filter { !$0.isEmpty }.joined(separator: " · "))
                    .ccText(font: .cc.sm, color: .cc.mutedForeground).lineLimit(1)
                Text(Date(timeIntervalSince1970: TimeInterval(item.viewedAt)), format: .dateTime.month().day().hour().minute())
                    .ccText(font: .cc.sm, color: .cc.mutedForeground)
                if item.progress == -1 { Text("已看完").ccText(font: .cc.sm, color: .cc.primary) }
                else if let progress = item.progress, progress > 0 {
                    Text("看到 \(BiliFormatters.duration(progress))").ccText(font: .cc.sm, color: .cc.primary)
                }
            }
        }.padding(.vertical, 4)
    }
}
