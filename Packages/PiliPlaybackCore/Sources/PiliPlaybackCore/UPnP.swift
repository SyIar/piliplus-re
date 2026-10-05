import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct UPnPService: Hashable, Sendable {
    public let type: String
    public let controlURL: URL
}
public struct UPnPRenderer: Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let location: URL
    public let transport: UPnPService
    public let rendering: UPnPService?
    public static func parse(_ data: Data, location: URL) throws -> Self {
        let delegate = DeviceParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard data.count <= 1024 * 1024, parser.parse() else { throw UPnPError.invalidDescription }
        let base = delegate.base.flatMap(URL.init(string:)) ?? location
        func resolve(_ entry: [String: String]) -> UPnPService? {
            guard let type = entry["serviceType"], let path = entry["controlURL"],
                  let url = URL(string: path, relativeTo: base)?.absoluteURL,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host == location.host else { return nil }
            return UPnPService(type: type, controlURL: url)
        }
        let services = delegate.services.compactMap(resolve)
        guard let transport = services.first(where: { $0.type.hasPrefix("urn:schemas-upnp-org:service:AVTransport:") }) else {
            throw UPnPError.unsupportedDevice
        }
        return Self(id: delegate.udn ?? location.absoluteString, name: delegate.name ?? location.host ?? "DLNA",
                    location: location, transport: transport,
                    rendering: services.first { $0.type.hasPrefix("urn:schemas-upnp-org:service:RenderingControl:") })
    }
}
public enum UPnPError: LocalizedError {
    case invalidDescription, unsupportedDevice, soap(String)
    public var errorDescription: String? {
        switch self {
        case .invalidDescription: "无法读取投屏设备信息"
        case .unsupportedDevice: "设备未提供 DLNA 播放服务"
        case let .soap(value): "投屏设备返回错误：\(value)"
        }
    }
}
public enum UPnPSOAP {
    public static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    public static func envelope(action: String, service: String, arguments: [(String, String)]) -> Data {
        let argumentsXML = arguments.map { "<\($0.0)>\(escape($0.1))</\($0.0)>" }.joined()
        return Data("<?xml version=\"1.0\" encoding=\"utf-8\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body><u:\(action) xmlns:u=\"\(escape(service))\">\(argumentsXML)</u:\(action)></s:Body></s:Envelope>".utf8)
    }
    public static func values(_ data: Data) throws -> [String: String] {
        let delegate = ValueParser()
        let parser = XMLParser(data: data); parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard data.count <= 1024 * 1024, parser.parse() else { throw UPnPError.invalidDescription }
        if let error = delegate.values["errorCode"] { throw UPnPError.soap(delegate.values["errorDescription"] ?? error) }
        return delegate.values
    }
    public static func metadata(url: URL, title: String, mime: String) -> String {
        "<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\"><item id=\"0\" parentID=\"-1\" restricted=\"1\"><dc:title>\(escape(title))</dc:title><upnp:class>object.item.videoItem</upnp:class><res protocolInfo=\"http-get:*:\(escape(mime)):*\">\(escape(url.absoluteString))</res></item></DIDL-Lite>"
    }
    public static func seconds(_ time: String?) -> Double? {
        guard let time else { return nil }
        let fields = time.split(separator: ":"); let parts = fields.compactMap { Double($0) }
        guard parts.count == 3, fields.count == parts.count, parts.allSatisfy({ $0.isFinite && $0 >= 0 }), parts[1] < 60, parts[2] < 60 else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
    public static func timestamp(_ time: Double) -> String {
        let value = Int(min(31_536_000, max(0, time.isFinite ? time : 0)))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
}

public enum UPnPNetwork {
    /// Discovery and the casting relay deliberately stay on a private IPv4 LAN.
    public static func isLocalIPv4(_ host: String) -> Bool {
        let fields = host.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 4, fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              fields.allSatisfy({ $0.count == 1 || $0.first != "0" }) else { return false }
        let bytes = fields.compactMap { UInt8($0) }
        guard bytes.count == 4 else { return false }
        return bytes[0] == 10 || (bytes[0] == 172 && (16...31).contains(bytes[1]))
            || (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 169 && bytes[1] == 254)
    }
    public static func validate(_ url: URL) throws {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, let host = url.host, isLocalIPv4(host) else {
            throw UPnPError.soap("请输入同一局域网内设备的 IPv4 描述地址")
        }
    }
}

private final class DeviceParser: NSObject, XMLParserDelegate {
    var name: String?, udn: String?, base: String?
    var services: [[String: String]] = []
    private var service: [String: String]?
    private var texts: [String] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        texts.append(""); if elementName == "service" { service = [:] }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if !texts.isEmpty { texts[texts.count - 1] += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = (texts.popLast() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "friendlyName", name == nil { name = text }
        if elementName == "UDN", udn == nil { udn = text }
        if elementName == "URLBase" { base = text }
        if ["serviceType", "controlURL"].contains(elementName) { service?[elementName] = text }
        if elementName == "service", let service { services.append(service); self.service = nil }
    }
}
private final class ValueParser: NSObject, XMLParserDelegate {
    var values: [String: String] = [:]
    private var texts: [String] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) { texts.append("") }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if !texts.isEmpty { texts[texts.count - 1] += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        values[elementName] = (texts.popLast() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
