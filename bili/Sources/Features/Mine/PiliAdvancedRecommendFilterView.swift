import SwiftUI

struct PiliAdvancedRecommendFilterView: View {
    @ObservedObject var libraryStore: LibraryStore
    @State private var draft = PiliAdvancedRecommendFilter()
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section("正则表达式") {
                TextField("标题，例如 广告|推广", text: $draft.titlePattern)
                TextField("分区，例如 游戏|娱乐", text: $draft.zonePattern)
            }.textInputAutocapitalization(.never).autocorrectionDisabled()
            Section {
                Toggle("已关注 UP 豁免推荐过滤", isOn: $draft.exemptsFollowed)
            } footer: { Text("根据推荐卡片的关注标记判断。黑名单仍然生效；相关视频不使用关注豁免。分区过滤仅对提供分区信息的卡片生效。") }
            if let error { Text(error).foregroundStyle(.red) }
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
