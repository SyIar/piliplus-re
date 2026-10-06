import ChunUI
import PhotosUI
import SwiftUI
import UIKit

struct PiliDynamicComposer: View {
    let api: BiliAPIClient
    private let identity: PiliAccountIdentity
    private let draftKey: String
    var onPublished: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ObservedObject private var sessionStore: SessionStore
    @State private var content: PiliDynamicDraft
    @State private var rich = RichCommentDraft()
    @State private var mentions: [PiliNamedResource] = []
    @State private var emotes: [BiliInlineEmote] = []
    @State private var focused = false
    @State private var inputMode = RichCommentInputMode.keyboard
    @State private var height: CGFloat = 140
    @State private var photos: [PhotosPickerItem] = []
    @State private var picker: PickerKind?
    @State private var restored = false
    @State private var loadingPhotos = false
    @State private var sending = false
    @State private var published = false
    @State private var needsDraftRecovery = false
    @State private var error: String?
    @State private var revision = 0
    @State private var timed = false
    @State private var publishDate = Date().addingTimeInterval(3600)
    enum PickerKind: String, Identifiable { case mention, topic, vote; var id: String { rawValue } }

    init(api: BiliAPIClient, initial: PiliDynamicDraft = .init(), onPublished: @escaping () -> Void = {}) {
        self.api = api; self.onPublished = onPublished
        identity = PiliAccountIdentity(api.requestSnapshot(purpose: .main))
        draftKey = "\(identity.mid).dynamic.\(initial.editingID ?? initial.repostID ?? "new")"
        _sessionStore = ObservedObject(wrappedValue: api.sessionStore)
        _content = State(initialValue: initial)
    }
    private var accountValid: Bool { identity.matches(api.requestSnapshot(purpose: .main)) }
    var body: some View {
        NavigationStack {
            Form {
                if !accountValid { Text("账号已切换或未登录，请重新打开编辑器").foregroundStyle(.red) }
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                if needsDraftRecovery {
                    Button("备份无法读取的草稿并新建") { Task {
                        do { try await PiliDraftStorage.shared.archive(key: draftKey); needsDraftRecovery = false; error = nil; revision += 1 }
                        catch { self.error = error.localizedDescription }
                    } }
                }
                Section {
                    TextField("标题（可选）", text: $content.title)
                    RichCommentTextView(draft: $rich, isFocused: $focused, inputMode: inputMode, inputViewHeight: 240,
                        emotes: emotes, dynamicTypeSize: dynamicType, onFocusChange: { focused = $0 },
                        onEditorTap: { focused = true }, onHeightChange: { height = $0 })
                        .frame(height: min(320, max(140, height)))
                        .accessibilityIdentifier("pili.dynamic.editor")
                    HStack(spacing: 18) {
                        Button { inputMode = inputMode == .keyboard ? .emotes : .keyboard; focused = true } label: { Image(systemName: "face.smiling") }.accessibilityLabel("表情")
                        Button { picker = .mention; focused = false } label: { Image(systemName: "at") }.accessibilityLabel("提及用户")
                        Button { picker = .topic; focused = false } label: { Image(systemName: "number") }.accessibilityLabel("选择话题")
                        Button { picker = .vote; focused = false } label: { Image(systemName: "chart.bar.xaxis") }.accessibilityLabel("添加投票")
                        PhotosPicker(selection: $photos, maxSelectionCount: max(1, 9 - content.pictures.count - rich.images.count), matching: .images) { Image(systemName: "photo") }
                            .disabled(content.pictures.count + rich.images.count >= 9).accessibilityLabel("添加图片")
                    }.buttonStyle(.borderless)
                    if loadingPhotos { ProgressView("处理图片") }
                    ForEach(content.pictures) { picture in
                        HStack {
                            CachedRemoteImage(url: URL(string: picture.url), targetPixelSize: 180) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }.frame(height: 72)
                            Spacer(); Button("移除", role: .destructive) { content.pictures.removeAll { $0.id == picture.id } }.buttonStyle(.borderless)
                        }
                    }
                    ForEach(rich.images) { image in
                        HStack {
                            PiliDraftThumbnail(bytes: image.data).frame(width: 80, height: 72)
                            Spacer(); Button("移除", role: .destructive) { rich.images.removeAll { $0.id == image.id }; revision += 1 }.buttonStyle(.borderless)
                        }
                    }
                    if content.repostID != nil { Label("转发动态", systemImage: "arrowshape.turn.up.right") }
                    if content.topicID != nil {
                        HStack { Text("#\(content.topicName)#"); Spacer(); Button("移除") { content.topicID = nil; content.topicName = "" }.buttonStyle(.borderless) }
                    }
                    if content.voteID != nil {
                        HStack { Label(content.voteTitle, systemImage: "chart.bar"); Spacer(); Button("移除") { content.voteID = nil }.buttonStyle(.borderless) }
                    }
                }
                Section("发布设置") {
                    Toggle("仅自己可见", isOn: $content.privatePost)
                    Picker("评论权限", selection: $content.commentPolicy) { Text("全部").tag(0); Text("关闭评论").tag(1); Text("精选评论").tag(2) }
                    if content.editingID == nil {
                        Toggle("定时发布", isOn: $timed)
                        if timed { DatePicker("发布时间", selection: $publishDate, in: Date()..., displayedComponents: [.date, .hourAndMinute]) }
                    }
                    Text("草稿按账号保存在本机；发布失败时保留内容。").font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(!restored || sending || !accountValid)
            .navigationTitle(content.editingID == nil ? "发布动态" : "编辑动态")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(sending) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "发布中" : "发布") { Task { await publish() } }
                        .disabled(!restored || sending || loadingPhotos || !accountValid || needsDraftRecovery)
                        .accessibilityIdentifier("pili.dynamic.publish")
                }
            }
            .interactiveDismissDisabled(sending)
            .sheet(item: $picker) { kind in
                switch kind {
                case .mention:
                    PiliResourcePicker(title: "提及用户", load: { try await api.piliMentions(keyword: $0) }) { item in
                        mentions.removeAll { $0.id == item.id }; mentions.append(item)
                        rich = rich.insertingText("@\(item.name) ", at: rich.selection)
                    }
                case .topic:
                    PiliResourcePicker(title: "话题", load: { try await api.piliTopics(keyword: $0) }) { item in content.topicID = item.id; content.topicName = item.name }
                case .vote:
                    PiliVoteCreator(api: api, identity: identity) { id, title in content.voteID = id; content.voteTitle = title }
                }
            }
            .task { await restore() }
            .task(id: "\(revision):\(published)") {
                guard restored, !published, !needsDraftRecovery else { return }
                do { try await Task.sleep(for: .milliseconds(600)); if !published { try await saveDraft() } }
                catch is CancellationError {} catch { self.error = "草稿保存失败：\(error.localizedDescription)" }
            }
            .onChange(of: rich.elements) { _, _ in syncContent() }
            .onChange(of: content) { _, _ in if restored { revision += 1 } }
            .onChange(of: timed) { _, value in content.scheduledAt = value ? publishDate : nil }
            .onChange(of: publishDate) { _, value in if timed { content.scheduledAt = value } }
            .onChange(of: photos) { _, selected in Task { await loadPhotos(selected) } }
            .onDisappear { if restored && !published && !needsDraftRecovery { Task { try? await saveDraft() } } }
        }
    }
    private func syncContent() {
        content.tokens = Self.tokens(from: rich.elements, mentions: mentions)
    }
    static func tokens(from elements: [RichCommentDraftElement], mentions: [PiliNamedResource]) -> [PiliContentToken] {
        let names = mentions.sorted { $0.name.count > $1.name.count }
        guard !names.isEmpty else { return elements.map { element in
            if case .emote(let text) = element { return .init(text: text, type: 9) }
            return .init(text: element.serializedString)
        } }
        let pattern = "@(" + names.map { NSRegularExpression.escapedPattern(for: $0.name) }.joined(separator: "|") + ")(?=\\s|[，。！？,.!?]|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return elements.flatMap { element -> [PiliContentToken] in
            if case .emote(let text) = element { return [.init(text: text, type: 9)] }
            let text = element.serializedString as NSString
            var result: [PiliContentToken] = [], cursor = 0
            for match in regex.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
                if match.range.location > cursor { result.append(.init(text: text.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))) }
                let name = text.substring(with: match.range(at: 1))
                let item = names.first { $0.name == name }!
                result.append(.init(text: text.substring(with: match.range), type: 2, businessID: String(item.id)))
                cursor = NSMaxRange(match.range)
            }
            if cursor < text.length { result.append(.init(text: text.substring(from: cursor))) }
            return result
        }
    }
    private func restore() async {
        guard !restored else { return }
        do {
            if let saved = try await PiliDraftStorage.shared.load(key: draftKey) {
                content = saved.0
                rich.images = saved.1.map { .init(id: $0.id, sourceIdentifier: nil, data: $0.data) }
            }
        } catch { self.error = "已有草稿无法读取：\(error.localizedDescription)"; needsDraftRecovery = true }
        rich.elements = content.tokens.map { $0.type == 9 ? .emote($0.text) : .text($0.text) }
        mentions = content.tokens.filter { $0.type == 2 }.compactMap { token in
            guard let id = Int(token.businessID) else { return nil }
            return .init(id: id, name: token.text.hasPrefix("@") ? String(token.text.dropFirst()) : token.text)
        }
        timed = content.scheduledAt != nil; publishDate = content.scheduledAt ?? Date().addingTimeInterval(3600)
        restored = true
        emotes = (try? await api.fetchCommentEmotes()) ?? []
    }
    private func saveDraft() async throws {
        guard !published, !needsDraftRecovery else { return }
        try await PiliDraftStorage.shared.save(content, images: rich.images.map { .init(id: $0.id, data: $0.data) }, key: draftKey)
    }
    private func loadPhotos(_ selected: [PhotosPickerItem]) async {
        guard !loadingPhotos, !selected.isEmpty else { return }
        loadingPhotos = true; defer { loadingPhotos = false; photos = [] }
        do {
            for item in selected.prefix(max(0, 9 - content.pictures.count - rich.images.count)) {
                try Task.checkCancellation()
                guard let data = try await item.loadTransferable(type: Data.self), let jpeg = await PiliImagePreparation.jpeg(data) else { throw PiliOfflineError.message("无法读取图片，单张原图需小于 40 MB") }
                rich.images.append(.init(sourceIdentifier: item.itemIdentifier, data: jpeg))
            }
            revision += 1
        } catch { self.error = error.localizedDescription }
    }
    private func publish() async {
        guard !sending, accountValid else { return }
        sending = true; error = nil; defer { sending = false }
        do {
            syncContent()
            try content.validate(pendingImages: rich.images.count)
            // Upload success is retained in the draft, so retrying the final
            // publication never uploads the same photos again.
            while let image = rich.images.first {
                let uploaded = try await api.uploadPiliContentImage(image.data, identity: identity)
                content.pictures.append(.init(url: uploaded.imageURL, width: uploaded.width, height: uploaded.height))
                rich.images.removeFirst(); try await saveDraft()
            }
            _ = try await api.publishPiliDynamic(content, identity: identity)
            published = true
            try? await PiliDraftStorage.shared.remove(key: draftKey)
            onPublished(); dismiss()
        } catch { self.error = error.localizedDescription; try? await saveDraft() }
    }
}

struct PiliDraftThumbnail: View {
    let bytes: Data
    @State private var image: UIImage?
    var body: some View {
        Group { if let image { Image(uiImage: image).resizable().scaledToFit() } else { ProgressView() } }
            .task { if let data = await PiliImagePreparation.jpeg(bytes, maxPixelSize: 180) { image = UIImage(data: data) } }
    }
}

struct PiliResourcePicker: View {
    let title: String
    let load: (String) async throws -> [PiliNamedResource]
    let select: (PiliNamedResource) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var items: [PiliNamedResource] = []
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(items) { item in
                    Button { select(item); dismiss() } label: {
                        VStack(alignment: .leading) { Text(item.name); if !item.subtitle.isEmpty { Text(item.subtitle).font(.caption).foregroundStyle(.secondary) } }
                    }
                }
            }.navigationTitle(title).searchable(text: $query)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                .task(id: query) {
                    let requested = query; loading = true; error = nil
                    do {
                        try await Task.sleep(for: .milliseconds(250))
                        let values = try await load(requested)
                        try Task.checkCancellation()
                        items = values; loading = false
                    } catch is CancellationError {} catch { if requested == query { self.error = error.localizedDescription; loading = false } }
                }
        }
    }
}

private struct PiliVoteCreator: View {
    let api: BiliAPIClient
    let identity: PiliAccountIdentity
    let onCreate: (Int, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var options = ["", ""]
    @State private var choices = 1
    @State private var days = 7
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("投票标题", text: $title)
                ForEach(options.indices, id: \.self) { index in TextField("选项 \(index + 1)", text: $options[index]) }
                if options.count < 20 { Button("添加选项") { options.append("") } }
                Stepper("最多选择 \(choices) 项", value: $choices, in: 1...options.count)
                Stepper("\(days) 天后结束", value: $days, in: 1...365)
                if let error { Text(error).foregroundStyle(.red) }
            }.disabled(busy).navigationTitle("发起投票")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button("创建") { Task {
                        busy = true; defer { busy = false }
                        do { let id = try await api.createPiliVote(title: title, options: options, multiple: choices, days: days, identity: identity); onCreate(id, title); dismiss() }
                        catch { self.error = error.localizedDescription }
                    } }.disabled(busy) }
                }.interactiveDismissDisabled(busy)
        }
    }
}
