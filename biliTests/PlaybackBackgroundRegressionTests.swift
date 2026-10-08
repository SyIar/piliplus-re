import Combine
import Foundation
import PiliPlaybackCore
import XCTest

@testable import bili

final class PlaybackBackgroundRegressionTests: XCTestCase {
    @MainActor
    func testDefaultsWrittenOffMainActorSafelyReachPlaybackPreferences() async throws {
        let preferences = PiliPlaybackPreferences.shared
        let previous = preferences.order
        let target: PlaybackOrder = previous == .repeatOne ? .sequential : .repeatOne
        let key = PiliPlaybackPreferences.orderKey
        let rawValue = target.rawValue
        defer { preferences.setOrder(previous) }
        let received = expectation(description: "Preferences delivered on main thread")
        let subscription = preferences.$order.dropFirst().first(where: { $0 == target }).sink { _ in
            XCTAssertTrue(Thread.isMainThread)
            received.fulfill()
        }
        defer { subscription.cancel() }

        // This is the notification path in all four supplied crash reports.
        await Task.detached {
            UserDefaults.standard.set(rawValue, forKey: key)
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
        }.value
        await fulfillment(of: [received], timeout: 3)
        XCTAssertEqual(preferences.order, target)
    }

    @MainActor
    func testIndefiniteTimestampsCannotReachPlaybackUIIntegerConversions() {
        let clock = PlayerPlaybackClock()
        clock.update(time: 12, duration: 100, force: true)
        clock.update(time: .nan, duration: .infinity, force: true)
        XCTAssertEqual(clock.currentTime, 12)
        XCTAssertNil(clock.duration)
        clock.updateSeekPreview(progress: .nan)
        XCTAssertNil(clock.seekPreviewProgress)
        for number in [Double.nan, .infinity, -.infinity, Double(Int.max), -1] {
            XCTAssertEqual(PlaybackNumericValue.integer(number), 0)
        }
        XCTAssertEqual(PlaybackNumericValue.integer(42.5), 42)
    }
}
