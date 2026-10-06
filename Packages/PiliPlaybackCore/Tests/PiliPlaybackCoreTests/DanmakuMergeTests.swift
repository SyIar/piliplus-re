import Testing
@testable import PiliPlaybackCore

@Test func duplicateDanmakuCountsDistinctAuthorsAndUnknownMessages() {
    let groups = DanmakuMerge.groups([
        .init(id: "a", time: 1, text: "哈哈", style: "scroll", sender: "alice"),
        .init(id: "b", time: 2, text: "哈哈", style: "scroll", sender: "alice"),
        .init(id: "c", time: 3, text: "哈哈", style: "scroll", sender: "bob"),
        .init(id: "d", time: 4, text: "哈哈", style: "scroll", sender: nil),
        .init(id: "d", time: 4, text: "哈哈", style: "scroll", sender: nil)
    ])
    #expect(groups == [.init(representativeID: "a", count: 3)])
}

@Test func mergingRespectsVideoTimeWindowStyleAndInvalidTime() {
    let input: [DanmakuMerge.Sample] = [
        .init(id: "c", time: 15, text: "same", style: "scroll", sender: nil),
        .init(id: "b", time: 14.9, text: "same", style: "top", sender: nil),
        .init(id: "a", time: 14.8, text: "same", style: "scroll", sender: nil),
        .init(id: "bad", time: .nan, text: "same", style: "scroll", sender: nil)
    ]
    #expect(DanmakuMerge.groups(input).map(\.representativeID) == ["a", "b", "c"])
    #expect(DanmakuMerge.groups(input) == DanmakuMerge.groups(input.reversed()))
    #expect(DanmakuMerge.groups(input, window: 0).isEmpty)
}
