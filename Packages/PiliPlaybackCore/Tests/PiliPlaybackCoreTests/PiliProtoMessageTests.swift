import Foundation
import XCTest
@testable import PiliPlaybackCore

final class PiliProtoMessageTests: XCTestCase {
    func testUnknownFieldsSurviveSettingsEdit() throws {
        // A future fixed32 field and a noncanonical varint must survive verbatim.
        let unknown = Data([0x95, 0x06, 1, 2, 3, 4, 0x98, 0x06, 0x81, 0x00])
        var toggle = PiliProtoMessage(); toggle.set(1, integer: 0); toggle.set(2, string: "提醒")
        var setting = PiliProtoMessage(); setting.set(1, message: toggle)
        var decoded = try PiliProtoMessage(data: setting.data + unknown)
        var changed = try decoded.message(1); changed.set(1, integer: 1); decoded.set(1, message: changed)
        XCTAssertTrue(decoded.data.starts(with: unknown))
        XCTAssertEqual(try decoded.message(1).integer(1), 1)
        XCTAssertEqual(try decoded.message(1).string(2), "提醒")
        XCTAssertEqual(try PiliProtoMessage(data: decoded.data), decoded)
    }
    func testRejectsMalformedAndOversizedFramesWithoutOverflow() {
        for data in [Data([0]), Data([8, 0x80]), Data([10, 255, 255, 255, 255, 255, 255, 255, 255, 127]), Data([8] + Array(repeating: 255, count: 10)), Data([11])] {
            XCTAssertThrowsError(try PiliProtoMessage(data: data))
        }
        XCTAssertThrowsError(try PiliProtoMessage(data: Data(repeating: 0, count: 20), limit: 10))
    }
    func testNestedRepeatedAndIntegerBoundary() throws {
        var a = PiliProtoMessage(); a.set(1, integer: Int.max); a.set(2, string: "一")
        var b = PiliProtoMessage(); b.set(1, integer: 0); b.set(2, string: "二")
        var message = PiliProtoMessage(); message.set(5, messages: [a, b])
        let decoded = try PiliProtoMessage(data: message.data)
        XCTAssertEqual(try decoded.messages(5).map { $0.integer(1) }, [Int.max, 0])
        XCTAssertEqual(try decoded.messages(5).map { $0.string(2) }, ["一", "二"])
        XCTAssertEqual(try decoded.message(99), PiliProtoMessage())
    }
}
