import SwiftUI
import ChunUI

struct PiliContentImageExportView: View {
    let document: PiliContentImageDocument
    @State private var files: [URL] = []
    @State private var error: String?
    @State private var loading = true
    @State private var saving = false
    @State private var loadID = UUID()
    @PiliDismiss private var dismiss
    var body: some View {
        NavigationStack {
            PiliForm {
                Section { Text(document.author).piliFont(.baseBold); Text(document.text).lineLimit(8) }
                if loading { ProgressView("生成完整内容图片") }
                if let error { Text(error).foregroundStyle(.secondary) }
                if !loading, files.isEmpty { Button("重试") { loadID = UUID() } }
                if !files.isEmpty {
                    Text("已生成 \(files.count) 张图片，包含完整文字和附图。长内容会自动分页。")
                    ShareLink(items: files) { PiliLabel("分享图片", systemImage: "square.and.arrow.up") }
                    PiliIconButton(saving ? "正在保存" : "保存全部到相册", systemImage: "square.and.arrow.down") {
                        saving = true
                        Task {
                            defer { saving = false }
                            do { try await PiliContentImageExport.save(files); error = "已保存到相册" }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(saving)
                }
            }.navigationTitle("保存\(document.title)").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(saving) } }
                .task(id: loadID) {
                    loading = true; error = nil; defer { loading = false }
                    do {
                        let urls = try await PiliContentImageExport.render(document)
                        if Task.isCancelled { PiliMediaCapture.remove(urls.first); return }
                        files = urls
                    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                }
                .onDisappear { PiliMediaCapture.remove(files.first) }
        }
    }
}


struct PiliDynamicExportView: View {
    let api: BiliAPIClient
    let id: String
    @State private var document: PiliContentImageDocument?
    @State private var error: String?
    @State private var revision = UUID()
    var body: some View {
        Group {
            if let document { PiliContentImageExportView(document: document) }
            else if let error { VStack(spacing: 16) { Text(error); Button("重新加载完整动态") { revision = UUID() } }.padding() }
            else { ProgressView("读取完整动态") }
        }.task(id: revision) {
            error = nil
            do {
                let data = try await api.piliContentRead("/x/polymer/web-dynamic/v1/detail", query: ["id": id, "features": "itemOpusStyle,onlyfansVote"])
                let item = try data["item"].piliDecode(DynamicFeedItem.self)
                guard !Task.isCancelled, item.idStr == id else { throw CancellationError() }
                document = .dynamic(item)
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
