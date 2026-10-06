import XCTest
@testable import bili

@MainActor
final class PiliCommentDanmakuExtensionsTests: XCTestCase {
    func testXMLAuthorIdentitySurvivesOfflineRoundTripAndMerging() throws {
        let xml = Data("<i><d p=\"1,1,25,16777215,0,0,alice,1\">哈哈</d><d p=\"2,1,25,16777215,0,0,bob,2\">哈哈</d><d p=\"3,1,25,16777215,0,0,alice,3\">哈哈</d></i>".utf8)
        let items = try DanmakuXMLParser(cid: 10).parse(data: xml)
        let persisted = try JSONEncoder().encode(items.map(PiliOfflineDanmaku.init))
        let restored = try JSONDecoder().decode([PiliOfflineDanmaku].self, from: persisted).map(\.item)
        XCTAssertEqual(restored.map(\.senderHash), ["alice", "bob", "alice"])
        let merged = DanmakuItem.mergingDuplicates(restored)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.displayText, "哈哈 ×2")
        XCTAssertEqual(merged.first?.text, "哈哈", "Keep the original content for actions and exports")
    }

    func testOldOfflineDanmakuAndSettingsRemainReadable() throws {
        let data = Data(#"{"id":"old","time":1,"mode":1,"fontSize":25,"color":16777215,"text":"hello"}"#.utf8)
        let item = try JSONDecoder().decode(PiliOfflineDanmaku.self, from: data).item
        XCTAssertNil(item.senderHash)
        XCTAssertEqual(item.displayText, "hello")
        var settings = DanmakuSettings.default
        settings.mergesDuplicates = true
        settings.opacity = 0
        let decoded = try JSONDecoder().decode(DanmakuSettings.self, from: JSONEncoder().encode(settings.normalized))
        XCTAssertTrue(decoded.mergesDuplicates)
        XCTAssertEqual(decoded.opacity, 0.25)
    }

    func testProtobufAuthorIdentityIsDecoded() throws {
        // id=1, progress=1000, mode=1, midHash="abc", content="same".
        let payload: [UInt8] = [8, 1, 16, 232, 7, 24, 1, 50, 3, 97, 98, 99, 58, 4, 115, 97, 109, 101]
        let items = try DanmakuSegmentProtobufParser(cid: 10, segmentIndex: 1).parse(data: Data([10, UInt8(payload.count)] + payload))
        XCTAssertEqual(items.first?.senderHash, "abc")
        XCTAssertEqual(items.first?.text, "same")
    }
}
