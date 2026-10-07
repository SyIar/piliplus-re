import XCTest
@testable import bili

final class HomeFeedDensityPreferenceTests: XCTestCase {
    @MainActor
    func testPhoneKeepsTwoColumnsAtPortraitAndLandscapeWidths() throws {
        for width in [CGFloat(320), 390, 440, 852] {
            for mode in [HomeFeedLayout.doubleColumn, .borderedDoubleColumn] {
                let metrics = HomeFeedLayoutMetrics(mode: mode, containerWidth: width, allowsWideGrid: false)
                XCTAssertEqual(metrics.feedColumns.count, 2)
                let cover = try XCTUnwrap(metrics.doubleColumnFixedCoverSize)
                XCTAssertEqual(cover.width * 2 + 12 + metrics.feedHorizontalPadding * 2, width, accuracy: 0.01)
            }
        }
    }

    @MainActor
    func testTabletGridReflowsWithoutOverflowingTheAvailableWidth() throws {
        let windows: [(CGFloat, Int)] = [(0, 2), (375, 2), (744, 2), (768, 3), (1024, 4), (1366, 4)]
        for (width, count) in windows {
            let metrics = HomeFeedLayoutMetrics(mode: .doubleColumn, containerWidth: width, allowsWideGrid: true)
            XCTAssertEqual(metrics.feedColumns.count, count)
            if width == 0 {
                XCTAssertNil(metrics.doubleColumnFixedCoverSize)
            } else {
                let cover = try XCTUnwrap(metrics.doubleColumnFixedCoverSize)
                XCTAssertGreaterThan(cover.width, 0)
                XCTAssertEqual(cover.width * CGFloat(count) + CGFloat(count - 1) * 12
                               + metrics.feedHorizontalPadding * 2, width, accuracy: 0.01)
                XCTAssertEqual(cover.width / cover.height, 16.0 / 9.0, accuracy: 0.01)
            }
        }
    }

    @MainActor
    func testExplicitSingleColumnPreferenceRemainsSingleColumnOnTablet() {
        for mode in [HomeFeedLayout.singleColumn, .borderedSingleColumn] {
            XCTAssertEqual(HomeFeedLayoutMetrics(mode: mode, containerWidth: 1024, allowsWideGrid: true).feedColumns.count, 1)
        }
    }

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
