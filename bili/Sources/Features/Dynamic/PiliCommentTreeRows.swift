import PiliPlaybackCore
import SwiftUI
import ChunUI

/// Shared by video and dynamic reply sheets; their existing pagination and
/// account-bound reply actions remain the source of truth.
struct PiliCommentTreeRows<Item: Identifiable, Content: View>: View where Item.ID == Int {
    let rootID: Int
    let items: [Item]
    let parentID: (Item) -> Int?
    var highlightedID: Int? = nil
    @ViewBuilder let content: (Item) -> Content
    @AppStorage("piliplus.comments.tree") private var usesTree = true
    @State private var collapsed = Set<Int>()

    var body: some View {
        let tree = ReplyTree(rootID: rootID, entries: items.map { .init(id: $0.id, parentID: parentID($0)) })
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("回复排列", selection: $usesTree) {
                    Text("平铺").tag(false)
                    Text("树状").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ui.comments.tree.mode")
                if usesTree && !collapsed.isEmpty {
                    Button("全部展开") { collapsed.removeAll() }
                        .font(.cc.sm).fixedSize()
                }
            }.padding(16)
            if usesTree {
                ForEach(tree.visibleRows(collapsed: collapsed)) { row in
                    VStack(alignment: .leading, spacing: 0) {
                        if row.descendantCount > 0 {
                            Button {
                                if !collapsed.insert(row.id).inserted { collapsed.remove(row.id) }
                            } label: {
                                PiliLabel(collapsed.contains(row.id) ? "展开 \(row.descendantCount) 条回复" : "收起回复", systemImage: collapsed.contains(row.id) ? "chevron.right" : "chevron.down")
                                    .font(.cc.sm).padding(.vertical, 10).padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("ui.comments.tree.fold.\(row.id)")
                        }
                        if let item = byID[row.id] { content(item) }
                        else {
                            PiliLabel("上级回复尚未加载或已删除", systemImage: "bubble.left")
                                .font(.cc.sm).foregroundStyle(.secondary).padding(16)
                        }
                    }
                    .padding(.leading, CGFloat(min(row.depth, 4)) * 14)
                    .accessibilityValue("第 \(row.depth + 1) 层回复")
                    .id(row.id)
                    Divider()
                }
            } else {
                ForEach(items) { item in content(item).id(item.id); Divider() }
            }
        }
        .onChange(of: highlightedID, initial: true) { _, id in
            if let id { collapsed.subtract(tree.ancestors(of: id)) }
        }
        .onChange(of: rootID) { _, _ in collapsed.removeAll() }
    }
}
