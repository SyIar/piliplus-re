import XCTest
@testable import bili

final class PiliSuperResolutionTests: XCTestCase {
    func testUpscalingBudgetKeepsAspectAndCapsOutput() throws {
        let efficiency = try XCTUnwrap(PiliSuperResolutionPolicy.outputSize(width: 640, height: 360, target: CGSize(width: 1920, height: 1080), mode: 1))
        XCTAssertEqual(efficiency, CGSize(width: 960, height: 540))
        let quality = try XCTUnwrap(PiliSuperResolutionPolicy.outputSize(width: 1920, height: 1080, target: CGSize(width: 3840, height: 2160), mode: 2))
        XCTAssertEqual(quality, CGSize(width: 2560, height: 1440))
        XCTAssertNil(PiliSuperResolutionPolicy.outputSize(width: 1920, height: 1080, target: CGSize(width: 640, height: 360), mode: 2))
        XCTAssertNil(PiliSuperResolutionPolicy.outputSize(width: 3840, height: 2160, target: CGSize(width: 7680, height: 4320), mode: 2))
        XCTAssertNil(PiliSuperResolutionPolicy.outputSize(width: 640, height: 360, target: CGSize(width: CGFloat.nan, height: 1080), mode: 2))
    }
}
