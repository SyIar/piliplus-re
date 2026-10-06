import SwiftUI
import ChunUI
import PiliPlaybackCore

struct PiliMessageSettingsView: View {
    let api: BiliAPIClient
    var settingType = 0
    @State private var title = "消息设置"
    @State private var items: [PiliIMSetting] = []
    @State private var identity: PiliAccountIdentity?
    @State private var error: String?
    @State private var loading = false
    @State private var mutating = false
    var body: some View {
        PiliList {
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(Color.cc.destructive); Button("重试") { Task { await load() } } }
            ForEach(items) { item in
                if item.kind == 1 {
                    Toggle(isOn: Binding(get: { item.isOn }, set: { save(item.toggled($0)) })) { label(item) }
                } else if !item.choices.isEmpty {
                    Section(item.title) {
                        ForEach(Array(item.choices.enumerated()), id: \.offset) { index, choice in
                            Button { save(item.selecting(index)) } label: {
                                HStack { Text(choice.string(2)); Spacer(); if choice.integer(3) == 1 { PiliIcon(systemName: "checkmark") } }
                            }
                        }
                    }
                } else if item.id == 26 {
                    NavigationLink { PiliMessageKeywordView(api: api) } label: { label(item) }
                } else if item.id == 12 {
                    NavigationLink { PiliRelationsView(api: api, kind: .blocked) } label: { label(item) }
                } else if item.isPage && item.parentType > 0 && item.parentType != settingType {
                    NavigationLink { PiliMessageSettingsView(api: api, settingType: item.parentType) } label: { label(item) }
                } else if let url = item.url {
                    Link(destination: url) { label(item) }
                } else if !item.title.isEmpty { label(item) }
            }
        }.disabled(mutating).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .task { identity = .init(api.requestSnapshot(purpose: .main)); await load() }
            .refreshable { await load() }
    }
    private func label(_ item: PiliIMSetting) -> some View {
        VStack(alignment: .leading) { Text(item.title); if !item.subtitle.isEmpty { Text(item.subtitle).font(.cc.sm).foregroundStyle(.secondary) } }
    }
    private func load() async {
        guard let identity, !loading else { return }; loading = true; defer { loading = false }
        do {
            var request = PiliProtoMessage(); request.set(1, integer: settingType)
            let reply = try await api.piliIM("GetImSettings", message: request, identity: identity)
            items = try PiliIMSetting.decode(reply); if !reply.string(1).isEmpty { title = reply.string(1) }; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func save(_ value: PiliIMSetting) {
        guard let identity, !mutating else { return }; mutating = true
        Task {
            defer { mutating = false }
            do {
                _ = try await api.piliIM("SetImSettings", message: value.updateRequest, identity: identity, write: true)
                if let index = items.firstIndex(where: { $0.id == value.id }) { items[index] = value }; error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct PiliMessageKeywordView: View {
    let api: BiliAPIClient
    @State private var identity: PiliAccountIdentity?
    @State private var words: [String] = []
    @State private var input = ""
    @State private var limit = 20
    @State private var characterLimit = 20
    @State private var busy = false
    @State private var error: String?
    @State private var removal: String?
    var body: some View {
        PiliForm {
            Section("新关键词") {
                TextField("屏蔽词", text: $input)
                Button("添加") { mutate("KeywordBlockingAdd", word: input.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || input.count > characterLimit || words.count >= limit)
                Text("最多 \(limit) 个，每个最多 \(characterLimit) 字").font(.cc.sm).foregroundStyle(.secondary)
            }
            Section("已屏蔽") {
                ForEach(words, id: \.self) { word in HStack { Text(word); Spacer(); Button("删除", role: .destructive) { removal = word } } }
            }
            if let error { Text(error).foregroundStyle(Color.cc.destructive); Button("重试") { Task { await load() } } }
        }.disabled(busy).navigationTitle("私信关键词屏蔽")
            .task { identity = .init(api.requestSnapshot(purpose: .main)); await load() }
            .piliConfirmation("删除这个屏蔽词？", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) {
                if let word = removal { PiliAlertButton("删除 \(word)", role: .destructive) { removal = nil; mutate("KeywordBlockingDelete", word: word) } }
            }
    }
    private func load() async {
        guard let identity else { return }
        do {
            let reply = try await api.piliIM("KeywordBlockingList", identity: identity)
            words = try reply.messages(1).map { $0.string(1) }
            limit = max(1, reply.integer(2)); characterLimit = max(1, reply.integer(3)); error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func mutate(_ method: String, word: String) {
        guard let identity, !busy, !word.isEmpty else { return }; busy = true
        Task {
            defer { busy = false }
            do {
                var request = PiliProtoMessage(); request.set(1, string: word)
                _ = try await api.piliIM(method, message: request, identity: identity, write: true)
                input = ""; await load()
            } catch { self.error = error.localizedDescription }
        }
    }
}
