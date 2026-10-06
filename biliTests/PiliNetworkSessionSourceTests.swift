import Foundation
import XCTest
@testable import bili

final class PiliNetworkSessionSourceTests: XCTestCase {
    func testNetworkRefreshCannotRetireASessionBeforeTaskRegistration() async throws {
        let source = BiliNetworkSessionSource(Self.session())
        let request = URLRequest(url: URL(string: "https://session.test/resource")!)
        let count = try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<120 {
                group.addTask {
                    if index.isMultiple(of: 3) { source.replace(with: Self.session()) }
                    let (data, response) = try await BiliNetworkRetry.data(
                        taskFactory: { source.task(for: $0, completion: $1) },
                        request: request, policy: .piliSingleRead
                    )
                    XCTAssertEqual(data, Data("ok".utf8))
                    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
                    return 1
                }
            }
            var completed = 0
            for try await value in group { completed += value }
            return completed
        }
        XCTAssertEqual(count, 120)
    }

    private nonisolated static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PiliSessionSourceURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private nonisolated final class PiliSessionSourceURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("ok".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
