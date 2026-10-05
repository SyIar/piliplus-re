import Foundation
import XCTest
@testable import bili

final class PiliCastingRelayTests: XCTestCase {
    @MainActor
    func testSelectedOfflineFileSupportsHeadRangesAndCapabilityPath() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cast-\(UUID().uuidString).mp4")
        let data = Data((0..<256).map(UInt8.init))
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let host = try await PiliCastingMediaHost.offlineForTesting(file: file)
        defer { host.stop() }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: host.url)
        request.setValue("bytes=10-19", forHTTPHeaderField: "Range")
        let (rangeData, rangeResponse) = try await session.data(for: request)
        XCTAssertEqual(rangeData, data.subdata(in: 10..<20))
        XCTAssertEqual((rangeResponse as? HTTPURLResponse)?.statusCode, 206)
        XCTAssertEqual((rangeResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range"), "bytes 10-19/256")
        request.httpMethod = "HEAD"
        let (headData, headResponse) = try await session.data(for: request)
        XCTAssertTrue(headData.isEmpty)
        XCTAssertEqual((headResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Length"), "10")
        request.httpMethod = "GET"; request.setValue("bytes=999-", forHTTPHeaderField: "Range")
        let (_, invalidRange) = try await session.data(for: request)
        XCTAssertEqual((invalidRange as? HTTPURLResponse)?.statusCode, 416)
        let unprefixed = host.url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("video.mp4")
        let (_, missingCapability) = try await session.data(from: unprefixed)
        XCTAssertEqual((missingCapability as? HTTPURLResponse)?.statusCode, 404)
        let (_, unregisteredFile) = try await session.data(from: host.url.deletingLastPathComponent().appendingPathComponent("other.mp4"))
        XCTAssertEqual((unregisteredFile as? HTTPURLResponse)?.statusCode, 404)
    }
}
