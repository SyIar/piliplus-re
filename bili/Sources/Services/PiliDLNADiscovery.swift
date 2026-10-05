import Combine
import Darwin
import Foundation
import PiliPlaybackCore

@MainActor
final class PiliDLNADiscovery: ObservableObject {
    @Published private(set) var devices: [UPnPRenderer] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    private let client = PiliDLNAClient()
    private var source: DispatchSourceRead?
    private var descriptor: Int32 = -1
    private var timeoutTask: Task<Void, Never>?
    private var fetchTasks: [Task<Void, Never>] = []
    private var seen: Set<String> = []
    private var generation = UUID()

    func search() {
        stop(); generation = UUID(); devices = []; seen = []; errorMessage = nil
        do {
            _ = try PiliLANAddress.currentIPv4()
            let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard fd >= 0 else { throw URLError(.cannotConnectToHost) }
            descriptor = fd
            var local = sockaddr_in()
            local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); local.sin_family = sa_family_t(AF_INET)
            local.sin_port = 0; local.sin_addr.s_addr = INADDR_ANY
            let bound = withUnsafePointer(to: &local) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            guard bound == 0, fcntl(fd, F_SETFL, O_NONBLOCK) != -1 else {
                Darwin.close(fd); descriptor = -1; throw URLError(.cannotConnectToHost)
            }
            let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            reader.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.receive() } }
            reader.setCancelHandler { Darwin.close(fd) }
            source = reader; reader.resume(); isSearching = true
            var target = sockaddr_in()
            target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); target.sin_family = sa_family_t(AF_INET)
            target.sin_port = UInt16(1900).bigEndian
            _ = "239.255.255.250".withCString { inet_pton(AF_INET, $0, &target.sin_addr) }
            for type in ["urn:schemas-upnp-org:service:AVTransport:1", "urn:schemas-upnp-org:device:MediaRenderer:1"] {
                let message = Data("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: \(type)\r\n\r\n".utf8)
                let sent = message.withUnsafeBytes { bytes in
                    withUnsafePointer(to: &target) { pointer in
                        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
                guard sent >= 0 else { throw UPnPError.soap("无法搜索设备，请检查本地网络权限，或手动添加设备") }
            }
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                self?.source?.cancel(); self?.source = nil; self?.descriptor = -1; self?.isSearching = false
            }
        } catch { stop(); errorMessage = error.localizedDescription }
    }
    func add(_ text: String) {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "设备描述地址格式不正确"; return
        }
        fetch(url, manual: true)
    }
    func stop() {
        generation = UUID(); timeoutTask?.cancel(); timeoutTask = nil
        source?.cancel(); source = nil; descriptor = -1; isSearching = false
        fetchTasks.forEach { $0.cancel() }; fetchTasks = []
    }
    private func receive() {
        guard descriptor >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = recv(descriptor, &buffer, buffer.count, 0)
            guard count > 0 else { break }
            let text = String(decoding: buffer.prefix(count), as: UTF8.self)
            for line in text.components(separatedBy: "\r\n") {
                let fields = line.split(separator: ":", maxSplits: 1)
                if fields.count == 2, fields[0].lowercased() == "location",
                   let url = URL(string: fields[1].trimmingCharacters(in: .whitespacesAndNewlines)) { fetch(url, manual: false) }
            }
        }
    }
    private func fetch(_ url: URL, manual: Bool) {
        if !manual, !seen.insert(url.absoluteString).inserted { return }
        guard fetchTasks.count < 64 else { return }
        let token = generation
        fetchTasks.append(Task { [weak self, client] in
            do {
                let renderer = try await client.device(at: url)
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.devices.removeAll { $0.id == renderer.id }; self.devices.append(renderer)
                self.devices.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                if manual { self.errorMessage = nil }
            } catch {
                guard let self, !Task.isCancelled, self.generation == token, manual else { return }
                self.errorMessage = error.localizedDescription
            }
        })
    }
    deinit { source?.cancel(); timeoutTask?.cancel(); fetchTasks.forEach { $0.cancel() } }
}
