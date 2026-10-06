import SwiftUI
import ChunUI

struct PiliCommentKeywordSettingsView: View {
    @AppStorage(PiliCommentKeywordFilter.key) private var stored = ""
    @State private var draft = ""
    @State private var saved = false
    var body: some View {
        PiliForm {
            Section("每行一个关键词") {
                TextEditor(text: $draft).frame(minHeight: 200).autocorrectionDisabled().textInputAutocapitalization(.never)
                Text("按评论正文匹配，不区分英文大小写；最多 200 个词、每词 200 字。楼中楼和回复预览同样过滤。保存后重新打开评论页或刷新生效。")
                    .font(.cc.sm).foregroundStyle(.secondary)
                Button("保存") { stored = PiliCommentKeywordRules(draft).words.joined(separator: "\n"); draft = stored; saved = true }
                if saved { Text("已保存").foregroundStyle(.secondary) }
            }
        }.navigationTitle("评论关键词过滤").onAppear { draft = stored }.onChange(of: draft) { if draft != stored { saved = false } }
    }
}
