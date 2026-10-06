import Testing
@testable import PiliPlaybackCore

@Test func replyTreeSupportsOutOfOrderPagesMissingParentsAndFolding() {
    let first = ReplyTree(rootID: 1, entries: [.init(id: 4, parentID: 3), .init(id: 2, parentID: 1)])
    #expect(first.rows.map(\.id) == [2, 3, 4])
    #expect(first.rows.first { $0.id == 3 }?.isMissing == true)
    let next = ReplyTree(rootID: 1, entries: [.init(id: 4, parentID: 3), .init(id: 2, parentID: 1), .init(id: 3, parentID: 2)])
    #expect(next.rows.map(\.id) == [2, 3, 4])
    #expect(next.rows.map(\.depth) == [0, 1, 2])
    #expect(next.rows[0].descendantCount == 2)
    #expect(next.visibleRows(collapsed: [2]).map(\.id) == [2])
    #expect(next.ancestors(of: 4) == [2, 3])
}

@Test func replyTreeBreaksCyclesAndPreservesEveryUniqueReply() {
    let tree = ReplyTree(rootID: 1, entries: [.init(id: 2, parentID: 3), .init(id: 3, parentID: 2), .init(id: 4, parentID: 4), .init(id: 4, parentID: 1)])
    #expect(Set(tree.rows.map(\.id)) == [2, 3, 4])
    #expect(tree.rows.count == 3)
}

@Test func replyTreeHandlesDeepThreadsWithoutRecursiveLayoutOrTraversal() {
    let tree = ReplyTree(rootID: 1, entries: (2...10_000).map { .init(id: $0, parentID: $0 - 1) })
    #expect(tree.rows.count == 9_999)
    #expect(tree.rows.first?.descendantCount == 9_998)
    #expect(tree.visibleRows(collapsed: [2]).count == 1)
}
