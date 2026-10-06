import SwiftUI
import ChunUI

struct PiliAdvancedRecommendFilterView: View {
    @ObservedObject var libraryStore: LibraryStore
    @State private var draft = PiliAdvancedRecommendFilter()
    @State private var error: String?
    @PiliDismiss private var dismiss
    var body: some View {
        PiliForm {
            Section("正则表达式") {
                PiliSettingAction(title: "标题") { TextField("例如 广告|推广", text: $draft.titlePattern).multilineTextAlignment(.trailing) }
                PiliSettingAction(title: "分区") { TextField("例如 游戏|娱乐", text: $draft.zonePattern).multilineTextAlignment(.trailing) }
            }.textInputAutocapitalization(.never).autocorrectionDisabled()
            Section {
                Toggle("已关注 UP 免过滤", isOn: $draft.exemptsFollowed)
            } footer: { Text("仅适用于首页中标记为已关注的 UP；黑名单仍生效。分区过滤需要卡片提供分区信息。") }
            if let error { Text(error).foregroundStyle(Color.cc.destructive) }
        }
        .navigationTitle("进阶推荐过滤").navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = libraryStore.advancedRecommendFilter }
        .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button("保存") {
                do { try libraryStore.setAdvancedRecommendFilter(draft); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        } }
    }
}
