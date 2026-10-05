import XCTest
@testable import bili

final class PiliCommentActionsTests: XCTestCase {
    func testMutuallyExclusiveReactionsPreserveCounts() throws {
        let comment = try JSONDecoder().decode(Comment.self, from: Data(#"{"rpid":7,"like":9,"action":1}"#.utf8))
        var state = PiliCommentState(comment: comment)
        state.apply(.dislike(true))
        XCTAssertEqual(state.reaction, 2)
        XCTAssertEqual(state.likeCount, 8)
        state.apply(.dislike(false))
        XCTAssertEqual(state.reaction, 0)
        XCTAssertEqual(state.likeCount, 8)
        state.apply(.like(true))
        state.apply(.like(true))
        XCTAssertEqual(state.likeCount, 9, "Repeated acknowledgement must not increment twice")
        state.apply(.delete)
        XCTAssertTrue(state.deleted)
    }

    func testModerationPermissionsUseCommentAuthorAndContentOwner() throws {
        let root = try JSONDecoder().decode(Comment.self, from: Data(#"{"rpid":7,"root":0,"member":{"mid":"100"}}"#.utf8))
        let reply = try JSONDecoder().decode(Comment.self, from: Data(#"{"rpid":8,"root":7,"member":{"mid":"100"}}"#.utf8))
        XCTAssertTrue(PiliCommentPermissions(comment: root, accountMID: 100, ownerMID: 200).canDelete)
        XCTAssertFalse(PiliCommentPermissions(comment: root, accountMID: 100, ownerMID: 200).canPin)
        XCTAssertTrue(PiliCommentPermissions(comment: root, accountMID: 200, ownerMID: 200).canPin)
        XCTAssertFalse(PiliCommentPermissions(comment: reply, accountMID: 200, ownerMID: 200).canPin)
        XCTAssertFalse(PiliCommentPermissions(comment: root, accountMID: 300, ownerMID: 200).canDelete)
        XCTAssertFalse(PiliCommentPermissions(comment: root, accountMID: 0, ownerMID: 0).canPin)
    }

    func testPinnedFlagAcceptsWebPayloadVariants() throws {
        for json in [#"{"rpid":7,"reply_control":{"is_up_top":true}}"#, #"{"rpid":7,"up_action":{"top":1}}"#] {
            XCTAssertTrue(try JSONDecoder().decode(Comment.self, from: Data(json.utf8)).isPinnedByOwner)
        }
        XCTAssertFalse(try JSONDecoder().decode(Comment.self, from: Data(#"{"rpid":7}"#.utf8)).isPinnedByOwner)
    }
}
