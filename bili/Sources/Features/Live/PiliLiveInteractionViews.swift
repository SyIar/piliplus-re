import SwiftUI
import ChunUI
import UIKit

struct PiliLiveInteractionView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var viewModel: LiveRoomViewModel
    @ObservedObject var store: PiliSuperChatStore
    var compact = false
    @State private var showsComposer = false
    @State private var showsHistory = false
    @State private var showsChat = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Button { showsChat = true } label: { PiliIcon(systemName: "text.bubble") }.buttonStyle(.glass).accessibilityLabel("\u{76f4}\u{64ad}\u{804a}\u{5929}\u{4e0e}\u{5c4f}\u{853d}")
                Button { showsComposer = true } label: { PiliLabel("\u{53d1}\u{5f39}\u{5e55}", systemImage: "bubble.left.and.text.bubble.right") }
                    .buttonStyle(.glass).accessibilityIdentifier("live.send.open")
                Button { showsHistory = true } label: { PiliLabel("\u{9192}\u{76ee}\u{7559}\u{8a00}", systemImage: "bubble.left.and.exclamationmark.bubble.right") }
                    .buttonStyle(.glass).accessibilityIdentifier("live.superchat.open")
            }
            if !compact {
                TimelineView(.periodic(from: .now, by: 1)) { time in
                    let values = Array(store.visible(at: time.date).prefix(3))
                    ForEach(values) { item in PiliSuperChatCard(item: item, date: time.date) }
                }
            }
        }
        .piliSheet(isPresented: $showsChat) { PiliLiveChatView(viewModel: viewModel, store: viewModel.chatStore) }
        .piliSheet(isPresented: $showsComposer) { PiliLiveComposer(viewModel: viewModel) }
        .piliSheet(isPresented: $showsHistory) {
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
                    placeholder: { PiliIcon(systemName: "person.crop.circle.fill") }
                    .frame(width: 28, height: 28).clipShape(Circle())
                Text(item.name).font(.cc.base.bold()).lineLimit(1)
                Spacer(minLength: 4)
                Text("¥\(item.price)").piliFont(.baseBold).monospacedDigit()
            }
            Text(item.message).piliFont(.base).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Text(item.end > date ? "\u{5269}\u{4f59} \(Int(ceil(item.end.timeIntervalSince(date)))) \u{79d2}" : "\u{5c55}\u{793a}\u{5df2}\u{7ed3}\u{675f}")
                .piliFont(.sm).foregroundStyle(.secondary).monospacedDigit()
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
    @PiliDismiss private var dismiss
    var body: some View {
        NavigationStack {
            PiliList {
                Picker("\u{5c55}\u{793a}", selection: $store.mode) { Text("\u{5173}\u{95ed}").tag(0); Text("\u{6709}\u{6548}").tag(1); Text("\u{5168}\u{90e8}").tag(2) }
                    .pickerStyle(.segmented).accessibilityIdentifier("live.superchat.filter")
                if store.loading { ProgressView() }
                if let error = store.error { Text(error); Button("\u{91cd}\u{65b0}\u{52a0}\u{8f7d}") { store.load(roomID: roomID, api: api, force: true) } }
                TimelineView(.periodic(from: .now, by: 1)) { time in
                    let values = store.visible(at: time.date)
                    if values.isEmpty { Text(store.mode == 0 ? "\u{9192}\u{76ee}\u{7559}\u{8a00}\u{5df2}\u{5173}\u{95ed}" : "\u{6682}\u{65e0}\u{9192}\u{76ee}\u{7559}\u{8a00}").foregroundStyle(.secondary) }
                    ForEach(values) { item in
                        PiliSuperChatCard(item: item, date: time.date)
                            .contextMenu {
                                PiliIconButton("\u{590d}\u{5236}", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.message }
                                PiliIconButton("\u{4fdd}\u{5b58}", systemImage: "square.and.arrow.down") { export = item }
                                PiliIconButton("\u{4e3e}\u{62a5}", systemImage: "exclamationmark.bubble") { report = item }
                            }
                    }
                }
                Text("\u{4fdd}\u{7559}\u{672c}\u{6b21}\u{8fdb}\u{5165}\u{76f4}\u{64ad}\u{95f4}\u{63a5}\u{6536}\u{5230}\u{7684}\u{6700}\u{8fd1} 200 \u{6761}，\u{5386}\u{53f2}\u{63a5}\u{53e3}\u{8fd4}\u{56de}\u{8303}\u{56f4}\u{4ee5}\u{5e73}\u{53f0}\u{4e3a}\u{51c6}。").piliFont(.sm).foregroundStyle(.secondary)
            }.navigationTitle("\u{9192}\u{76ee}\u{7559}\u{8a00}").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("\u{5b8c}\u{6210}") { dismiss() } } }
                .onChange(of: store.mode) { _, _ in onModeChange() }
                .piliSheet(item: $report) { item in PiliSuperChatReportView(api: api, item: item, roomID: roomID) }
                .piliSheet(item: $export) { item in
                    PiliContentImageExportView(document: .init(title: "\u{9192}\u{76ee}\u{7559}\u{8a00}", author: "\(item.name) · ¥\(item.price)", text: item.message,
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
    @PiliDismiss private var dismiss
    var body: some View {
        NavigationStack {
            PiliForm {
                Text(item.message)
                TextField("\u{4e3e}\u{62a5}\u{539f}\u{56e0}", text: $reason, axis: .vertical).lineLimit(2...5)
                if let error { Text(error) }
                Button("\u{63d0}\u{4ea4}\u{4e3e}\u{62a5}") {
                    guard let identity else { return }; busy = true
                    Task {
                        defer { busy = false }
                        do { try await api.piliReportSuperChat(item, roomID: roomID, reason: reason, identity: identity); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(busy || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.navigationTitle("\u{4e3e}\u{62a5}\u{9192}\u{76ee}\u{7559}\u{8a00}").onAppear { if identity == nil { identity = .init(api.requestSnapshot()) } }
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
    @PiliDismiss private var dismiss
    var body: some View {
        NavigationStack {
            PiliForm {
                if let target = viewModel.liveReplyTarget {
                    HStack { Text("\u{56de}\u{590d} \(target.senderName ?? "\u{7528}\u{6237}")"); Spacer(); Button("\u{53d6}\u{6d88}\u{56de}\u{590d}") { viewModel.liveReplyTarget = nil } }
                }
                Section {
                    if let selected {
                        PiliLabel("\u{8868}\u{60c5}：\(selected.text)", systemImage: "face.smiling")
                        Button("\u{6539}\u{53d1}\u{6587}\u{5b57}") { self.selected = nil }
                    } else { TextField("\u{53d1}\u{4e00}\u{6761}\u{53cb}\u{5584}\u{7684}\u{5f39}\u{5e55}", text: $viewModel.liveDanmakuDraft, axis: .vertical).lineLimit(2...5) }
                    PiliIconButton(busy ? "\u{6b63}\u{5728}\u{53d1}\u{9001}" : "\u{53d1}\u{9001}\u{5f39}\u{5e55}", systemImage: "paperplane.fill") { send() }
                        .disabled(busy || (selected == nil && viewModel.liveDanmakuDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        .accessibilityIdentifier("live.send.submit")
                }.disabled(busy)
                if let error { Text(error).foregroundStyle(.secondary) }
                Section("\u{76f4}\u{64ad}\u{95f4}\u{8868}\u{60c5}") {
                    if loading { ProgressView() }
                    if emotes.isEmpty, !loading { Button("\u{91cd}\u{65b0}\u{52a0}\u{8f7d}\u{8868}\u{60c5}") { loadID = UUID() } }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 66))]) {
                        ForEach(emotes) { emote in
                            Button {
                                if emote.insertsText { selected = nil; viewModel.liveDanmakuDraft += emote.text }
                                else { selected = emote }
                            } label: {
                                VStack(spacing: 4) {
                                    CachedRemoteImage(url: URL(string: emote.image), targetPixelSize: 160) { $0.resizable().scaledToFit() }
                                        placeholder: { PiliIcon(systemName: "face.smiling") }
                                        .frame(height: 44)
                                    Text(emote.text).piliFont(.sm).lineLimit(1)
                                    if !emote.allowed { PiliIcon(systemName: "lock.fill").piliFont(.sm) }
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(.plain).disabled(!emote.allowed || busy)
                                .accessibilityLabel(emote.text + (emote.allowed ? "" : "，" + emote.reason))
                        }
                    }
                }
            }.navigationTitle("\u{53d1}\u{9001}\u{76f4}\u{64ad}\u{5f39}\u{5e55}").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("\u{53d6}\u{6d88}") { dismiss() }.disabled(busy) } }
                .task(id: loadID) {
                    if identity == nil { identity = .init(viewModel.api.requestSnapshot()) }
                    guard let identity, identity.mid > 0 else { error = "\u{8bf7}\u{5148}\u{767b}\u{5f55}\u{540e}\u{518d}\u{53d1}\u{9001}\u{5f39}\u{5e55}"; return }
                    loading = true; defer { loading = false }
                    do { emotes = try await viewModel.api.piliLiveEmotes(roomID: viewModel.roomID, identity: identity) }
                    catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                }
        }.piliInteractiveDismissDisabled(busy)
    }
    private func send() {
        guard !busy, let identity else { return }; busy = true; error = nil
        let message = selected?.id ?? viewModel.liveDanmakuDraft
        let isEmote = selected != nil
        let reply = viewModel.liveReplyTarget?.liveMetadata
        Task {
            defer { busy = false }
            do {
                try await viewModel.api.piliSendLive(roomID: viewModel.roomID, message: message, emote: isEmote, identity: identity, reply: reply)
                if !isEmote { viewModel.liveDanmakuDraft = "" }; viewModel.liveReplyTarget = nil; dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
