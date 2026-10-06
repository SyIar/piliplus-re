import XCTest
@testable import bili

final class HomeFeedDensityPreferenceTests: XCTestCase {
    @MainActor
    func testFreshInstallUsesTwoColumns() throws {
        let suite = "HomeFeedDensity.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(LibraryStore(userDefaults: defaults).homeFeedLayout, .doubleColumn)
    }

    @MainActor
    func testExistingSingleColumnMigratesOnceAndLaterChoicePersists() throws {
        for (old, expected) in [(HomeFeedLayout.singleColumn, HomeFeedLayout.doubleColumn),
                                (.borderedSingleColumn, .borderedDoubleColumn),
                                (.borderedDoubleColumn, .borderedDoubleColumn)] {
            let suite = "HomeFeedDensity.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(old.rawValue, forKey: "cc.bili.home.feedLayout.v1")
            let store = LibraryStore(userDefaults: defaults)
            XCTAssertEqual(store.homeFeedLayout, expected)
            store.setHomeFeedLayout(.singleColumn)
            XCTAssertEqual(LibraryStore(userDefaults: defaults).homeFeedLayout, .singleColumn)
        }
    }
}
