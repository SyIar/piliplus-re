import SwiftUI
import UIKit

struct PiliLiveInteractionView: View {
    @ObservedObject var viewModel: LiveRoomViewModel
    @ObservedObject var store: PiliSuperChatStore
    var compact = false
    @State private var showsComposer = false
    @State private var showsHistory = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button { showsComposer = true } label: { Label("发弹幕", systemImage: "bubble.left.and.text.bubble.right") }
                    .buttonStyle(.glass).accessibilityIdentifier("live.send.open")
                Button { showsHistory = true } label: { Label("醒目留言", systemImage: "bubble.left.and.exclamationmark.bubble.right") }
                    .buttonStyle(.glass).accessibilityIdentifier("live.superchat.open")
            }
            if !compact {
                TimelineView(.periodic(from: .now, by: 1)) { time in
                    let values = Array(store.visible(at: time.date).prefix(3))
                    ForEach(values) { item in PiliSuperChatCard(item: item, date: time.date) }
                }
            }
        }
        .sheet(isPresented: $showsComposer) { PiliLiveComposer(viewModel: viewModel) }
        .sheet(isPresented: $showsHistory) {
            PiliSuperChatHistoryView(store: store, api: viewModel.api, roomID: viewModel.roomID) {
                if store.mode != 0 { viewModel.resumeLiveDanmakuIfNeeded(); store.load(roomID: viewModel.roomID, api: viewModel.api) }
                else if !viewModel.isDanmakuEnabled { viewModel.stopLiveDanmaku(clearItems: false) }
            }
        }
    }
}

struct PiliSuperChatCard: View {
    let item: PiliSuperChat
    let date: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CachedRemoteImage(url: URL(string: item.face), targetPixelSize: 96) { $0.resizable().scaledToFill() }
                    placeholder: { Image(systemName: "person.crop.circle.fill") }
                    .frame(width: 28, height: 28).clipShape(Circle())
                Text(item.name).font(.subheadline.bold()).lineLimit(1)
                Spacer(minLength: 4)
                Text("¥\(item.price)").font(.headline).monospacedDigit()
            }
            Text(item.message).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Text(item.end > date ? "剩余 \(Int(ceil(item.end.timeIntervalSince(date)))) 秒" : "展示已结束")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: Double((item.color >> 16) & 255) / 255, green: Double((item.color >> 8) & 255) / 255,
            blue: Double(item.color & 255) / 255).opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.12)))
        .accessibilityIdentifier("live.superchat.\(item.id)")
    }
}

struct PiliSuperChatHistoryView: View {
    @ObservedObject var store: PiliSuperChatStore
    let api: BiliAPIClient
    let roomID: Int
    var onModeChange: () -> Void = {}
    @State private var report: PiliSuperChat?
    @State private var export: PiliSuperChat?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Picker("展示", selection: $store.mode) { Text("关闭").tag(0); Text("有效").tag(1); Text("全部").tag(2) }
                    .pickerStyle(.segmented).accessibilityIdentifier("live.superchat.filter")
                if store.loading { ProgressView() }
                if let error = store.error { Text(error); Button("重新加载") { store.load(roomID: roomID, api: api, force: true) } }
                TimelineView(.periodic(from: .now, by: 1)) { time in
                    let values = store.visible(at: time.date)
                    if values.isEmpty { Text(store.mode == 0 ? "醒目留言已关闭" : "暂无醒目留言").foregroundStyle(.secondary) }
                    ForEach(values) { item in
                        PiliSuperChatCard(item: item, date: time.date)
                            .contextMenu {
                                Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.message }
                                Button("保存", systemImage: "square.and.arrow.down") { export = item }
                                Button("举报", systemImage: "exclamationmark.bubble") { report = item }
                            }
                    }
                }
                Text("保留本次进入直播间接收到的最近 200 条，历史接口返回范围以平台为准。").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("醒目留言").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .onChange(of: store.mode) { _, _ in onModeChange() }
                .sheet(item: $report) { item in PiliSuperChatReportView(api: api, item: item, roomID: roomID) }
                .sheet(item: $export) { item in
                    PiliContentImageExportView(document: .init(title: "醒目留言", author: "\(item.name) · ¥\(item.price)", text: item.message,
                        pictures: [], source: "https://live.bilibili.com/\(roomID)"))
                }
        }
    }
}

private struct PiliSuperChatReportView: View {
    let api: BiliAPIClient
    let item: PiliSuperChat
    let roomID: Int
    @State private var identity: PiliAccountIdentity?
    @State private var reason = ""
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Text(item.message)
                TextField("举报原因", text: $reason, axis: .vertical).lineLimit(2...5)
                if let error { Text(error) }
                Button("提交举报") {
                    guard let identity else { return }; busy = true
                    Task {
                        defer { busy = false }
                        do { try await api.piliReportSuperChat(item, roomID: roomID, reason: reason, identity: identity); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(busy || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.navigationTitle("举报醒目留言").onAppear { if identity == nil { identity = .init(api.requestSnapshot()) } }
        }
    }
}

struct PiliLiveComposer: View {
    @ObservedObject var viewModel: LiveRoomViewModel
    @State private var identity: PiliAccountIdentity?
    @State private var emotes: [PiliLiveEmote] = []
    @State private var selected: PiliLiveEmote?
    @State private var loading = false
    @State private var loadID = UUID()
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let selected {
                        Label("表情：\(selected.text)", systemImage: "face.smiling")
                        Button("改发文字") { self.selected = nil }
                    } else { TextField("发一条友善的弹幕", text: $viewModel.liveDanmakuDraft, axis: .vertical).lineLimit(2...5) }
                    Button(busy ? "正在发送" : "发送弹幕", systemImage: "paperplane.fill") { send() }
                        .disabled(busy || (selected == nil && viewModel.liveDanmakuDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        .accessibilityIdentifier("live.send.submit")
                }.disabled(busy)
                if let error { Text(error).foregroundStyle(.secondary) }
                Section("直播间表情") {
                    if loading { ProgressView() }
                    if emotes.isEmpty, !loading { Button("重新加载表情") { loadID = UUID() } }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 66))]) {
                        ForEach(emotes) { emote in
                            Button {
                                if emote.insertsText { selected = nil; viewModel.liveDanmakuDraft += emote.text }
                                else { selected = emote }
                            } label: {
                                VStack(spacing: 4) {
                                    CachedRemoteImage(url: URL(string: emote.image), targetPixelSize: 160) { $0.resizable().scaledToFit() }
                                        placeholder: { Image(systemName: "face.smiling") }
                                        .frame(height: 44)
                                    Text(emote.text).font(.caption2).lineLimit(1)
                                    if !emote.allowed { Image(systemName: "lock.fill").font(.caption) }
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(.plain).disabled(!emote.allowed || busy)
                                .accessibilityLabel(emote.text + (emote.allowed ? "" : "，" + emote.reason))
                        }
                    }
                }
            }.navigationTitle("发送直播弹幕").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) } }
                .task(id: loadID) {
                    if identity == nil { identity = .init(viewModel.api.requestSnapshot()) }
                    guard let identity, identity.mid > 0 else { error = "请先登录后再发送弹幕"; return }
                    loading = true; defer { loading = false }
                    do { emotes = try await viewModel.api.piliLiveEmotes(roomID: viewModel.roomID, identity: identity) }
                    catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                }
        }.interactiveDismissDisabled(busy)
    }
    private func send() {
        guard !busy, let identity else { return }; busy = true; error = nil
        let message = selected?.id ?? viewModel.liveDanmakuDraft
        let isEmote = selected != nil
        Task {
            defer { busy = false }
            do {
                try await viewModel.api.piliSendLive(roomID: viewModel.roomID, message: message, emote: isEmote, identity: identity)
                if !isEmote { viewModel.liveDanmakuDraft = "" }; dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
