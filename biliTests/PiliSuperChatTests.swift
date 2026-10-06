import XCTest
@testable import bili

final class PiliSuperChatTests: XCTestCase {
    @MainActor
    func testSuperChatKeepsPriceLifetimeAndDeduplicatesSocketHistory() throws {
        let command: [String: Any] = ["cmd": "SUPER_CHAT_MESSAGE", "data": ["id": "701", "uid": 42, "price": 50,
            "message": "测试醒目留言", "start_time": 100, "end_time": 180, "user_info": ["uname": "观众"],
            "background_bottom_color": "#3264F0", "token": "report-token", "ts": 100]]
        let danmaku = try XCTUnwrap(LiveDanmakuService.parsedItems(for: command, roomID: 99, startDate: .now).first)
        let item = try XCTUnwrap(danmaku.superChat)
        XCTAssertEqual(item.price, 50)
        XCTAssertEqual(item.name, "观众")
        XCTAssertEqual(item.color, 0x3264F0)
        let store = PiliSuperChatStore()
        let oldMode = store.mode
        defer { store.mode = oldMode }
        store.mode = 1
        store.ingest([item, item])
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.visible(at: Date(timeIntervalSince1970: 150)).count, 1)
        XCTAssertTrue(store.visible(at: Date(timeIntervalSince1970: 180)).isEmpty)
        store.mode = 2
        XCTAssertEqual(store.visible(at: Date(timeIntervalSince1970: 200)).count, 1)
        store.mode = 0
        XCTAssertTrue(store.visible(at: .now).isEmpty)
    }
}
