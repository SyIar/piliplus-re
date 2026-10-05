import Foundation
import XCTest
@testable import bili

final class LiveCDNProbeCancellationTests: XCTestCase {
    func testCancellingAnActiveSampleStopsTheURLSessionTask() async throws {
        let started = expectation(description: "CDN response started")
        let stopped = expectation(description: "CDN request cancelled")
        stopped.assertForOverFulfill = false
        let finished = expectation(description: "probe returned after cancellation")
        StallingProbeURLProtocol.configure(started: started, stopped: stopped)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StallingProbeURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = LiveCDNProbeService(session: session)
        let task = Task {
            do {
                _ = try await service.probe(url: URL(string: "https://example.com/live.ts")!, headers: [:]) { _ in }
                XCTFail("A cancelled sample must not be reported as successful")
            } catch {
                XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
            }
            finished.fulfill()
        }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        await fulfillment(of: [finished, stopped], timeout: 4)
    }

    func testManifestSelectionRejectsUnsafeSchemesAndResolvesRelativeSegments() {
        let base = URL(string: "https://cdn.example.com/stream/live.m3u8")!
        XCTAssertEqual(LiveCDNProbeService.mediaURL(in: "#EXTM3U\n#EXTINF:4,\n../part.ts\n", relativeTo: base)?.absoluteString, "https://cdn.example.com/part.ts")
        XCTAssertNil(LiveCDNProbeService.mediaURL(in: "#EXTM3U\nfile:///etc/passwd", relativeTo: base))
        XCTAssertNil(LiveCDNProbeService.mediaURL(in: "#EXTM3U\n#EXT-X-ENDLIST", relativeTo: base))
    }
}

private final class StallingProbeURLProtocol: URLProtocol {
    private nonisolated final class Signals: @unchecked Sendable {
        let lock = NSLock()
        var started: XCTestExpectation?
        var stopped: XCTestExpectation?
        func set(_ start: XCTestExpectation, _ stop: XCTestExpectation) {
            lock.lock(); defer { lock.unlock() }
            started = start; stopped = stop
        }
        func signal(start: Bool) {
            lock.lock(); let value = start ? started : stopped; lock.unlock()
            value?.fulfill()
        }
    }
    private static let signals = Signals()
    static func configure(started: XCTestExpectation, stopped: XCTestExpectation) { signals.set(started, stopped) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "video/mp2t"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 0x47, count: 8192))
        Self.signals.signal(start: true)
        // Deliberately leave the response open, like a live stream with stalled chunks.
    }
    override func stopLoading() { Self.signals.signal(start: false) }
}
