import XCTest
@testable import bili

final class PiliLiveChatTests: XCTestCase {
    nonisolated static func message() -> [String: Any] {
        var head: [Any] = Array(repeating: 0, count: 16)
        head[15] = ["user": ["uid": 42, "base": ["name": "Viewer"], "medal": ["name": "Medal", "level": 7]],
            "extra": #"{"id_str":"9876543210987","dm_type":0,"reply_mid":55,"reply_uname":"Other"}"#] as [String: Any]
        return ["cmd": "DANMU_MSG", "info": [head, "hello", [42, "Viewer"], [], [], [], [], [], [], ["ts": 123, "ct": "report-signature"]]]
    }
    func testLiveMetadataPreservesReportIdentityAndReplyWithoutInferringFromDisplayText() throws {
        let item = try XCTUnwrap(LiveDanmakuService.parsedItems(for: Self.message(), roomID: 9, startDate: .now).first)
        let meta = try XCTUnwrap(item.liveMetadata)
        XCTAssertTrue(meta.canReport); XCTAssertEqual(meta.uid, 42); XCTAssertEqual(meta.id, "9876543210987")
        XCTAssertEqual(meta.timestamp, "123"); XCTAssertEqual(meta.signature, "report-signature")
        XCTAssertEqual(meta.replyUID, 55); XCTAssertEqual(meta.medalLevel, 7)
        let legacy = try XCTUnwrap(PiliLiveMessageMetadata(command: ["info": [[], "hello", [42, "Viewer"]]]))
        XCTAssertEqual(legacy.uid, 42); XCTAssertFalse(legacy.canReport)
    }
    func testLiveShieldBlocksExactUIDAndKeywordAndDeduplicatesRules() throws {
        let item = try XCTUnwrap(LiveDanmakuService.parsedItems(for: Self.message(), roomID: 9, startDate: .now).first)
        let raw = try JSONDecoder().decode(DynamicJSONValue.self, from: Data(#"{"shield_info":{"keyword_list":["sale","sale"],"shield_user_list":[{"uid":42,"uname":"Viewer"},{"uid":42,"uname":"Viewer"}]}}"#.utf8))
        let shield = PiliLiveShield(raw)
        XCTAssertEqual(shield.keywords, ["sale"]); XCTAssertEqual(shield.users.count, 1); XCTAssertFalse(shield.allows(item))
        XCTAssertTrue(PiliLiveShield(.null).allows(item))
        let advertised = DanmakuItem(id: "ad", time: 0, mode: 1, fontSize: 25, color: 0, text: "sale offer")
        XCTAssertFalse(shield.allows(advertised))
    }
}
