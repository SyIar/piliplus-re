import XCTest
@testable import bili

@MainActor
final class PiliContentParityTests: XCTestCase {
    func testCookieImportPreservesEncodedAndEqualsValuesAndRejectsNewlineInjection() {
        let values = PiliCookieImport.values(from: "Cookie: SESSDATA=abc%2Cdef==; DedeUserID=42; bili_jct=token; bad=x\r\nInjected: value")
        XCTAssertEqual(values["SESSDATA"], "abc%2Cdef==")
        XCTAssertEqual(values["DedeUserID"], "42")
        XCTAssertNil(values["bad"])
        let cookies = PiliCookieImport.webCookies(from: "SESSDATA=test; access_key=app-token")
        XCTAssertEqual(cookies.map(\.name), ["SESSDATA"])
        XCTAssertTrue(cookies.allSatisfy { $0.domain == ".bilibili.com" && $0.isSecure })
        let unrelated = HTTPCookie(properties: [.domain: "notbilibili.com", .path: "/", .name: "SESSDATA", .value: "test"])!
        XCTAssertFalse(BiliWebCookieStore.isStorableBiliCookie(unrelated))
    }
    func testReservationOnlyDynamicRetainsNumericCardIdentityAcrossDraftSave() throws {
        var draft = PiliDynamicDraft()
        draft.reservation = .init(id: 123, title: "直播", date: Date().addingTimeInterval(3600), subtype: 0)
        let restored = try JSONDecoder().decode(PiliDynamicDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored.reservation, draft.reservation)
        let data = try JSONEncoder().encode(restored.payload(mid: 42, uploadID: "test"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let request = try XCTUnwrap(json["dyn_req"] as? [String: Any])
        let card = try XCTUnwrap((request["attach_card"] as? [String: Any])?["common_card"] as? [String: Any])
        XCTAssertEqual(card["type"] as? Int, 14); XCTAssertEqual(card["biz_id"] as? Int, 123)
        XCTAssertEqual(card["reserve_lottery"] as? Int, 0)
    }
    func testVoteValidationDoesNotSilentlyDropBlankOptionsBeforeUploads() {
        XCTAssertThrowsError(try PiliVoteSubmission.validate(title: "投票", texts: ["A", "B", " "], choices: 1, duration: 3600))
        XCTAssertThrowsError(try PiliVoteSubmission.validate(title: "投票", texts: ["A", " A "], choices: 1, duration: 3600))
        XCTAssertThrowsError(try PiliVoteSubmission.validate(title: "投票", texts: ["A", "B"], choices: 3, duration: 3600))
        XCTAssertThrowsError(try PiliVoteSubmission.validate(title: "投票", texts: ["A", "B"], choices: 1, duration: -10))
        XCTAssertNoThrow(try PiliVoteSubmission.validate(title: "投票", texts: ["A", "B"], choices: 2, duration: 86400))
    }
}
