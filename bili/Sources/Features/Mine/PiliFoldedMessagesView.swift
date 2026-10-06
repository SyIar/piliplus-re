import SwiftUI
import PiliPlaybackCore

struct PiliFoldedMessagesView: View {
    let api: BiliAPIClient
    let viewModel: AccountMessageCenterViewModel
    let pageType: Int
    let title: String
    @State private var items: [PiliFoldedSession] = []
    @State private var pagination = PiliProtoMessage()
    @State private var hasMore = false
    @State private var identity: PiliAccountIdentity?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red); Button("重试") { Task { await load(reset: items.isEmpty) } } }
            ForEach(items) { item in
                if let session = item.session {
                    NavigationLink {
                        AccountPrivateMessageConversationView(session: session, viewModel: viewModel, onMarkedRead: {}, onConversationChanged: {})
                    } label: { label(item) }
                } else if let url = item.url { Link(destination: url) { label(item) } }
                else { label(item) }
            }
            if busy { ProgressView() }
            else if hasMore { Button("加载更多") { Task { await load(reset: false) } } }
            else if items.isEmpty && error == nil { Text("暂无消息").foregroundStyle(.secondary) }
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .task { identity = .init(api.requestSnapshot(purpose: .main)); await load(reset: true) }
            .refreshable { await load(reset: true) }
    }
    private func label(_ item: PiliFoldedSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(item.name); Spacer(); if item.unread > 0 { Text("\(item.unread)").foregroundStyle(.tint) } }
            Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }
    private func load(reset: Bool) async {
        guard let identity, !busy else { return }; busy = true; defer { busy = false }
        do {
            var request = PiliProtoMessage(); request.set(3, integer: pageType)
            if !reset { request.set(2, message: pagination) }
            let reply = try await api.piliIM("SessionSecondary", message: request, identity: identity)
            let received = try reply.messages(3).map(PiliFoldedSession.init)
            if reset { items = [] }
            var seen = Set(items.map(\.id)); items.append(contentsOf: received.filter { seen.insert($0.id).inserted })
            let next = try reply.message(1)
            hasMore = next.integer(2) == 1 && next != pagination && !received.isEmpty; pagination = next; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

nonisolated struct PiliFoldedSession: Identifiable, Sendable {
    let id: String
    let name: String
    let summary: String
    let unread: Int
    let session: AccountPrivateMessageSession?
    let url: URL?
    init(_ raw: PiliProtoMessage) throws {
        let identifier = try raw.message(1), info = try raw.message(2)
        let mid = try identifier.message(1).integer(1)
        id = identifier.data.base64EncodedString()
        name = info.string(1); summary = try raw.message(4).string(1); unread = try raw.message(3).integer(2)
        url = URL(string: raw.string(9))
        if mid > 0 {
            session = .init(talkerID: mid, actor: .init(mid: mid, name: name, avatarURLString: nil), preview: summary,
                timestamp: raw.integer(5) > 0 ? Date(timeIntervalSince1970: Double(raw.integer(5)) / 1_000_000) : nil,
                unreadCount: unread, lastMessageSequence: raw.integer(7), isPinned: raw.integer(6) == 1, isMuted: raw.integer(8) == 1)
        } else { session = nil }
    }
}
