import SwiftUI

struct PiliCommentTreeFixture: View {
    private struct Reply: Identifiable { let id: Int; let parent: Int; let text: String }
    @State private var replies = [
        Reply(id: 2, parent: 1, text: "第一层回复"),
        Reply(id: 3, parent: 2, text: "第二层回复"),
        Reply(id: 4, parent: 3, text: "第三层回复"),
        Reply(id: 5, parent: 6, text: "另一段讨论")
    ]
    var body: some View {
        NavigationStack {
            ScrollView {
                PiliCommentTreeRows(rootID: 1, items: replies, parentID: { $0.parent }) { reply in
                    Text(reply.text).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("ui.tree.reply.\(reply.id)")
                }
                if !replies.contains(where: { $0.id == 6 }) {
                    Button("加载下一页") { replies.append(Reply(id: 6, parent: 1, text: "补齐的上级回复")) }
                        .buttonStyle(.glass).padding()
                }
            }
            .navigationTitle("回复讨论")
        }
        .task {
            AppOrientationLock.restorePortrait()
            if UITestFixtureScenario.resetsPersistedState { UserDefaults.standard.set(true, forKey: "piliplus.comments.tree") }
        }
    }
}
