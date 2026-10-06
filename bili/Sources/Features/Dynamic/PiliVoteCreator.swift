import PhotosUI
import SwiftUI
import ChunUI

struct PiliVoteCreator: View {
    let api: BiliAPIClient
    let identity: PiliAccountIdentity
    var voteID: Int?
    let onCreate: (Int, String) -> Void
    @PiliDismiss private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var options = [PiliVoteOption(), PiliVoteOption()]
    @State private var imageVote = false
    @State private var choices = 1
    @State private var ends = Date().addingTimeInterval(7 * 86400)
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            PiliForm {
                TextField("投票标题", text: $title)
                TextField("说明（可选）", text: $description, axis: .vertical)
                Toggle("图片投票", isOn: $imageVote)
                ForEach($options) { $option in
                    Section {
                        TextField("选项", text: $option.text)
                        if imageVote { PiliVoteOptionPhoto(option: $option) }
                        if options.count > 2 {
                            Button("删除选项", role: .destructive) {
                                options.removeAll { $0.id == option.id }; choices = min(choices, options.count)
                            }
                        }
                    }
                }
                if options.count < 20 { Button("添加选项") { options.append(.init()) } }
                Stepper("最多选择 \(choices) 项", value: $choices, in: 1...max(1, options.count))
                DatePicker("结束时间", selection: $ends, in: Date()...Date().addingTimeInterval(90 * 86400))
                if let error { Text(error).foregroundStyle(Color.cc.destructive) }
                if busy || !loaded { ProgressView() }
            }.disabled(busy || !loaded).navigationTitle(voteID == nil ? "发起投票" : "编辑投票")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(busy || !loaded) }
                }.piliInteractiveDismissDisabled(busy)
                .task {
                    guard !loaded else { return }
                    do {
                        if let voteID {
                            let info = try await api.piliVote(id: voteID)
                            guard max(info["vote_publisher"].piliInt, info["uid"].piliInt) == identity.mid else { throw PiliOfflineError.message("只能修改自己的投票") }
                            title = info["title"].piliString; description = info["desc"].piliString
                            options = info["options"].piliArray.map { .init(text: $0["opt_desc"].piliString, imageURL: $0["img_url"].piliString) }
                            choices = max(1, min(info["choice_cnt"].piliInt, options.count)); imageVote = info["type"].piliInt == 1
                            ends = Date(timeIntervalSince1970: TimeInterval(info["end_time"].piliInt))
                        }
                        loaded = true
                    } catch { self.error = error.localizedDescription }
                }
        }
    }
    private func save() async {
        guard !busy, loaded else { return }; busy = true; error = nil; defer { busy = false }
        do {
            try PiliVoteSubmission.validate(title: title, texts: options.map(\.text), choices: choices, duration: Int(ends.timeIntervalSinceNow))
            guard !imageVote || options.allSatisfy({ $0.photo != nil || !$0.imageURL.isEmpty }) else { throw PiliOfflineError.message("请为每个选项添加图片") }
            for index in options.indices where imageVote && options[index].photo != nil {
                let upload = try await api.uploadPiliContentImage(options[index].photo!, identity: identity, biz: "vote")
                options[index].imageURL = upload.imageURL; options[index].photo = nil
            }
            let value = try await api.piliSaveVote(id: voteID, title: title, description: description, choices: choices,
                duration: Int(ends.timeIntervalSinceNow), options: options.map { ($0.text, imageVote ? $0.imageURL : "") }, identity: identity)
            onCreate(value, title); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct PiliVoteOption: Identifiable {
    let id = UUID()
    var text = ""
    var imageURL = ""
    var photo: Data?
}
private struct PiliVoteOptionPhoto: View {
    @Binding var option: PiliVoteOption
    @State private var selection: PhotosPickerItem?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading) {
            if let photo = option.photo { PiliDraftThumbnail(bytes: photo).frame(height: 90) }
            else if !option.imageURL.isEmpty {
                CachedRemoteImage(url: URL(string: option.imageURL), targetPixelSize: 180) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }.frame(height: 90)
            }
            PhotosPicker(selection: $selection, matching: .images) { PiliLabel("选择图片", systemImage: "photo") }
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(Color.cc.destructive) }
        }.task(id: selection) {
            guard let selection else { return }; loading = true; error = nil
            defer { loading = false }
            do {
                guard let data = try await selection.loadTransferable(type: Data.self), let photo = await PiliImagePreparation.jpeg(data) else { throw PiliOfflineError.message("无法读取此图片") }
                try Task.checkCancellation(); option.photo = photo
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}

nonisolated enum PiliVoteSubmission {
    static func validate(title: String, texts: [String], choices: Int, duration: Int) throws {
        let values = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 80,
              (2...20).contains(values.count), values.allSatisfy({ !$0.isEmpty && $0.count <= 100 }),
              Set(values).count == values.count, (1...values.count).contains(choices), (60...90 * 86400).contains(duration) else {
            throw PiliOfflineError.message("请填写标题、至少两个不同选项，结束时间需在 1 分钟到 90 天内")
        }
    }
}

extension BiliAPIClient {
    func piliSaveVote(id: Int?, title: String, description: String, choices: Int, duration: Int,
                      options: [(String, String)], identity: PiliAccountIdentity) async throws -> Int {
        try PiliVoteSubmission.validate(title: title, texts: options.map(\.0), choices: choices, duration: duration)
        let isImage = options.contains { !$0.1.isEmpty }
        guard !isImage || options.allSatisfy({ !$0.1.isEmpty }) else { throw BiliAPIError.missingPayload }
        var info: [String: PiliJSON] = ["title": .string(title), "desc": .string(description), "type": .int(isImage ? 1 : 0),
            "choice_cnt": .int(choices), "duration": .int(duration), "vote_publisher": .int(identity.mid), "only_fans_level": .int(0),
            "options": .array(options.map { .object(["opt_desc": .string($0.0), "img_url": .string($0.1)]) })]
        if let id { info["vote_id"] = .int(id) }
        let value = try await piliContentWrite(id == nil ? "/x/vote/create" : "/x/vote/update", body: .object(["vote_info": .object(info)]), identity: identity)
        let result = value["vote_id"].piliInt > 0 ? value["vote_id"].piliInt : id ?? 0
        guard result > 0 else { throw BiliAPIError.missingPayload }; return result
    }
}
