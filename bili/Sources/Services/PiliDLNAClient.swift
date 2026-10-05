import Darwin
import Foundation
import PiliPlaybackCore

nonisolated private final class PiliDLNARedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

nonisolated struct PiliDLNAClient: Sendable {
    private let session: URLSession
    init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 8; config.timeoutIntervalForResource = 12
        self.session = URLSession(configuration: config, delegate: PiliDLNARedirectDelegate(), delegateQueue: nil)
    }
    func device(at url: URL) async throws -> UPnPRenderer {
        try UPnPNetwork.validate(url)
        var request = URLRequest(url: url); request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode), data.count <= 1024 * 1024 else {
            throw UPnPError.invalidDescription
        }
        return try UPnPRenderer.parse(data, location: url)
    }
    @discardableResult
    func command(_ action: String, service: UPnPService, arguments: [(String, String)] = []) async throws -> [String: String] {
        try UPnPNetwork.validate(service.controlURL)
        var request = URLRequest(url: service.controlURL)
        request.httpMethod = "POST"; request.httpShouldHandleCookies = false
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service.type)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = UPnPSOAP.envelope(action: action, service: service.type, arguments: [("InstanceID", "0")] + arguments)
        let (data, response) = try await session.data(for: request)
        let values = try UPnPSOAP.values(data)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw UPnPError.soap("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return values
    }
}

nonisolated enum PiliLANAddress {
    static func currentIPv4() throws -> String {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { throw URLError(.notConnectedToInternet) }
        defer { freeifaddrs(pointer) }
        var addresses: [(String, String)] = []
        var next: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = next {
            defer { next = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  entry.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                  entry.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let value = String(cString: host)
            if UPnPNetwork.isLocalIPv4(value) { addresses.append((name, value)) }
        }
        guard let address = addresses.sorted(by: { $0.0 < $1.0 }).first?.1 else {
            throw UPnPError.soap("请将 iPhone 和电视连接到同一 Wi-Fi")
        }
        return address
    }
}
