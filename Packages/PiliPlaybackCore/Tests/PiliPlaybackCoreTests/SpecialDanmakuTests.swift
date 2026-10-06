import XCTest
@testable import PiliPlaybackCore

final class SpecialDanmakuTests: XCTestCase {
    func testMotionDelayEasingAndOpacityUseVideoTime() throws {
        let item = try XCTUnwrap(SpecialDanmaku(json: #"[0.1,0.2,"1-0",6,"高级弹幕",30,45,0.9,0.8,2000,1000,1,"",1]"#))
        XCTAssertEqual(item.position(at: 0.5).x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(item.position(at: 2).x, 0.2, accuracy: 0.0001)
        XCTAssertEqual(item.position(at: 3).y, 0.8, accuracy: 0.0001)
        XCTAssertEqual(item.position(at: 3).opacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(item.position(at: 1).x, 0.1, accuracy: 0.0001) // seeking backward
        XCTAssertEqual(item.rotationY, .pi / 4, accuracy: 0.0001)
        XCTAssertTrue(item.stroke)
    }
    func testPixelCoordinatesAndMalformedInputAreBounded() throws {
        let item = try XCTUnwrap(SpecialDanmaku(json: #"["960","540","0.5-0.5",4,"text",0,0]"#))
        XCTAssertEqual(item.startX, 0.5); XCTAssertEqual(item.startY, 0.5)
        XCTAssertEqual(item.endX, item.startX)
        XCTAssertNil(SpecialDanmaku(json: "[]"))
        XCTAssertNil(SpecialDanmaku(json: #"[0,0,"1-1",1e200,"text"]"#))
        XCTAssertNil(SpecialDanmaku(json: #"[0,0,"1-1",-1,"text"]"#))
        XCTAssertNil(SpecialDanmaku(json: "not json"))
    }
}
