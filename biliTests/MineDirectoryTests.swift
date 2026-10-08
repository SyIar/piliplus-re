import XCTest
@testable import bili

final class MineDirectoryTests: XCTestCase {
    @MainActor
    func testDirectoryOrderAndSearchUseTheSameCategories() {
        XCTAssertEqual(PiliSettingsCategory.allCases.map(\.rawValue), ["privacy", "recommendation", "audioVideo", "player", "appearance", "other", "webDAV", "about"])
        XCTAssertEqual(PiliSettingsCategory.matching(" CDN "), [.audioVideo])
        XCTAssertEqual(PiliSettingsCategory.matching("WebDAV"), [.webDAV])
        XCTAssertEqual(PiliSettingsCategory.matching(""), PiliSettingsCategory.allCases)
    }
    func testLevelSixUnknownNextExperienceDoesNotBreakAccountDecoding() throws {
        let json = #"{"isLogin":true,"mid":123,"money":637.5,"level_info":{"current_level":6,"current_exp":30000,"next_exp":"--"}}"#
        let user = try JSONDecoder().decode(NavUserInfo.self, from: Data(json.utf8))
        XCTAssertEqual(user.money, 637.5)
        XCTAssertEqual(user.levelInfo?.level, 6)
        XCTAssertNil(user.levelInfo?.next)
        let minimal = try JSONDecoder().decode(NavUserInfo.self, from: Data(#"{"isLogin":false}"#.utf8))
        XCTAssertNil(minimal.levelInfo)
    }
}
