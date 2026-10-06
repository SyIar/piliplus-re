import ChunUI
import SwiftUI

struct PiliNotesLibraryView: View {
    let api: BiliAPIClient
    let video: VideoItem?
    @ObservedObject private var sessionStore: SessionStore
    @State private var published = false
    @State private var items: [PiliNoteRecord] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var loading = false
    @State private var message: String?
    @State private var loadedVersion: Int?
    @State private var selection = Set<String>()
    @State private var editMode = EditMode.inactive
    init(api: BiliAPIClient, video: VideoItem? = nil) {
        self.api = api; self.video = video
        _sessionStore = ObservedObject(wrappedValue: api.sessionStore)
    }
    var body: some View {
        NavigationStack {
            PiliSelectionList(selection: $selection) {
                if let video, let aid = video.aid {
                    NavigationLink {
                        PiliNoteEditorView(api: api, aid: aid, initialTitle: video.title, noteID: nil, initialText: "", time: nil)
                    } label: { Label { Text("开始记笔记") } icon: { PikaIcon(PikaIcon.Name.edit) } }
                    PiliFullNoteEditorLink(api: api, aid: aid)
                } else {
                    Picker("类型", selection: $published) { Text("私人笔记").tag(false); Text("公开笔记").tag(true) }.pickerStyle(.segmented)
                }
                if let message { Text(message).ccText(font: .cc.sm, color: .cc.mutedForeground) }
                ForEach(items) { item in
                    NavigationLink {
                        PiliNoteReaderView(api: api, record: item, published: video != nil || published)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).ccText(font: .cc.baseBold, color: .cc.foreground)
                            Text(item.summary).ccText(font: .cc.sm, color: .cc.mutedForeground).lineLimit(3)
                            if let author = item.author { Text(author).ccText(font: .cc.sm, color: .cc.mutedForeground) }
                        }
                    }.tag(item.id)
                }
                if loading { ProgressView("加载笔记") }
                else if hasMore { Button("加载更多") { Task { await load() } } }
                else if items.isEmpty { Text("暂无笔记").ccText(font: .cc.base, color: .cc.mutedForeground) }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(video == nil ? "我的笔记" : "视频笔记")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await load(reset: true) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { AppHelper.shared.dismissSheet() } label: { PikaIcon(PikaIcon.Name.close) }.accessibilityLabel("关闭")
                }
                if video == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(editMode == .active ? "完成" : "选择") { editMode = editMode == .active ? .inactive : .active; selection.removeAll() }
                    }
                    if editMode == .active {
                        ToolbarItem(placement: .bottomBar) {
                            CCNeoButton("删除所选 \(selection.count) 条", variant: .danger, disabled: loading || selection.isEmpty) { confirmDelete() }
                        }
                    }
                }
            }
        }
        .task(id: "\(published)|\(api.requestSnapshot(purpose: .main).playbackCredentialVersion)") { await load(reset: true) }
    }
    private func load(reset: Bool = false) async {
        let version = api.requestSnapshot(purpose: .main).playbackCredentialVersion
        if reset { items = []; page = 1; hasMore = true; selection = []; loadedVersion = version }
        else if loading { return }
        let requestedPage = page, requestedMode = published
        loading = true; message = nil
        defer { if loadedVersion == version && published == requestedMode { loading = false } }
        do {
            let values = try await api.fetchPiliNotes(page: requestedPage, published: published, videoAID: video?.aid)
            guard !Task.isCancelled, api.requestSnapshot(purpose: .main).playbackCredentialVersion == version, published == requestedMode else { return }
            let seen = Set(items.map(\.id)); items.append(contentsOf: values.filter { !seen.contains($0.id) })
            hasMore = values.count == 10; page = requestedPage + 1; loadedVersion = version
        } catch {
            guard !Task.isCancelled, api.requestSnapshot(purpose: .main).playbackCredentialVersion == version else { return }
            message = error.localizedDescription
        }
    }
    private func confirmDelete() {
        let records = items.filter { selection.contains($0.id) }, mode = published
        guard let version = loadedVersion else { return }
        CCAlertCenter.shared.present(title: "删除 \(records.count) 条笔记？", message: "云端笔记将被删除。", actions: [
            CCAlertAction(title: "取消", role: .secondary),
            CCAlertAction(title: "删除", role: .destructive) {
                Task {
                    loading = true
                    do {
                        try await api.deletePiliNotes(records, published: mode, credentialVersion: version)
                        await load(reset: true)
                    } catch { message = error.localizedDescription; loading = false }
                }
            },
        ])
    }
}

struct PiliNoteReaderView: View {
    let api: BiliAPIClient
    let record: PiliNoteRecord
    let published: Bool
    @State private var detail: PiliNoteDetail?
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let detail {
                    Text(detail.title).ccText(font: .cc.lgBold, color: .cc.foreground)
                    ForEach(Array(detail.operations.enumerated()), id: \.offset) { _, operation in
                        PiliNoteOperationView(operation: operation)
                    }
                    if !published, !detail.forbidsEditing, let aid = detail.aid ?? record.aid {
                        PiliFullNoteEditorLink(api: api, aid: aid)
                    }
                    if !published, !detail.forbidsEditing, let aid = detail.aid ?? record.aid, detail.canEditAsText {
                        NavigationLink("编辑笔记") {
                            PiliNoteEditorView(api: api, aid: aid, initialTitle: detail.title, noteID: record.noteID,
                                               initialText: detail.plainText, time: nil)
                        }.buttonStyle(.glass)
                    }
                } else if let error { Text(error).ccText(font: .cc.sm, color: .cc.mutedForeground) }
                else { ProgressView() }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }
        .navigationTitle("笔记").navigationBarTitleDisplayMode(.inline)
        .task {
            do { detail = try await api.fetchPiliNote(record, published: published) }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct PiliNoteOperationView: View {
    let operation: DynamicJSONValue
    var body: some View {
        let object = operation.objectValueForDynamicParsing ?? [:]
        let attributes = object["attributes"]?.objectValueForDynamicParsing ?? [:]
        if let text = object["insert"]?.textValue {
            Text(text)
                .piliFont(.base)
                .bold(attributes["bold"] == .bool(true))
                .italic(attributes["italic"] == .bool(true))
                .underline(attributes["underline"] == .bool(true))
                .strikethrough(attributes["strike"] == .bool(true))
                .textSelection(.enabled)
        } else if let insert = object["insert"]?.objectValueForDynamicParsing,
                  let image = insert["image"]?.textValue, let url = URL(string: image), ["http", "https"].contains(url.scheme ?? "") {
            AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
        } else { Text("[嵌入内容]").ccText(font: .cc.sm, color: .cc.mutedForeground) }
    }
}

struct PiliNoteEditorView: View {
    let api: BiliAPIClient
    let aid: Int
    let time: Double?
    private let credentialVersion: Int
    private let draftKey: String
    @State private var noteID: String?
    @State private var title: String
    @State private var text: String
    @State private var published = false
    @State private var saving = false
    @State private var message: String?
    @State private var draftTask: Task<Void, Never>?
    @State private var saved = false
    init(api: BiliAPIClient, aid: Int, initialTitle: String, noteID: String?, initialText: String, time: Double?) {
        self.api = api; self.aid = aid; self.time = time
        let account = api.requestSnapshot(purpose: .main)
        credentialVersion = account.playbackCredentialVersion
        draftKey = "piliplus.note.draft.\(account.currentUserMID ?? 0).\(aid).\(noteID ?? "new")"
        let draft = UserDefaults.standard.dictionary(forKey: draftKey)
        _noteID = State(initialValue: noteID)
        _title = State(initialValue: draft?["title"] as? String ?? initialTitle)
        _text = State(initialValue: draft?["text"] as? String ?? initialText)
    }
    var body: some View {
        PiliForm {
            PiliFullNoteEditorLink(api: api, aid: aid)
            TextField("笔记标题", text: $title)
            TextEditor(text: $text).piliFont(.base).frame(minHeight: 260)
            if let time {
                Button("插入当前时间 \(Int(time) / 60):\(String(format: "%02d", Int(time) % 60))") {
                    text += "\n[\(Int(time) / 60):\(String(format: "%02d", Int(time) % 60))] "
                }
            }
            Toggle("公开笔记", isOn: $published)
            CCNeoButton(published ? "公开发布" : "保存到云端", variant: .primary, fullWidth: true, disabled: saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                if published {
                    CCAlertCenter.shared.present(title: "公开发布这条笔记？", message: "其他用户可以查看笔记内容。", actions: [
                        CCAlertAction(title: "取消", role: .secondary),
                        CCAlertAction(title: "发布", role: .destructive) { Task { await save() } },
                    ])
                } else { await save() }
            }
            if saving { ProgressView("保存中") }
            if let message { Text(message).ccText(font: .cc.sm, color: .cc.mutedForeground) }
            Text("编辑内容自动保存在本机草稿中，点击保存后才同步到当前主账号。").ccText(font: .cc.sm, color: .cc.mutedForeground)
        }
        .navigationTitle("编辑笔记").navigationBarTitleDisplayMode(.inline)
        .onChange(of: text) { _, _ in scheduleDraft() }
        .onChange(of: title) { _, _ in scheduleDraft() }
        .onDisappear { draftTask?.cancel(); if !saved { persistDraft() } }
    }
    private func scheduleDraft() {
        saved = false; draftTask?.cancel()
        draftTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(600)); persistDraft() } catch {}
        }
    }
    private func persistDraft() { UserDefaults.standard.set(["title": title, "text": text], forKey: draftKey) }
    private func save() async {
        guard !saving else { return }
        saving = true; message = nil; persistDraft()
        defer { saving = false }
        do {
            noteID = try await api.savePiliNote(aid: aid, noteID: noteID, title: title, text: text, published: published, credentialVersion: credentialVersion)
            draftTask?.cancel(); saved = true
            UserDefaults.standard.removeObject(forKey: draftKey)
            message = published ? "已提交公开笔记" : "笔记已保存"
        } catch { message = "保存失败，草稿已保留：\(error.localizedDescription)" }
    }
}

struct PiliFullNoteEditorLink: View {
    let api: BiliAPIClient
    let aid: Int
    var body: some View {
        NavigationLink("富文本笔记（图片与排版）") {
            PiliAccountWebView(api: api,
                url: URL(string: "https://www.bilibili.com/h5/note-app?oid=\(aid)&pagefrom=ugcvideo&is_stein_gate=0")!,
                title: "富文本笔记")
        }
    }
}
