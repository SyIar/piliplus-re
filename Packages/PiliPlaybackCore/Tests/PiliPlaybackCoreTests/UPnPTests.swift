import Foundation
import Testing
@testable import PiliPlaybackCore

@Test func rendererDescriptionResolvesRelativeServicesWithoutFollowingForeignHosts() throws {
    let location = URL(string: "http://192.168.1.3:8000/root/description.xml")!
    let xml = "<root xmlns='urn:schemas-upnp-org:device-1-0'><device><friendlyName>客厅 &amp; TV</friendlyName><UDN>uuid:test</UDN><serviceList><service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><controlURL>/control/av</controlURL></service></serviceList></device></root>"
    let device = try UPnPRenderer.parse(Data(xml.utf8), location: location)
    #expect(device.name == "客厅 & TV")
    #expect(device.transport.controlURL.absoluteString == "http://192.168.1.3:8000/control/av")
    #expect(throws: (any Error).self) { try UPnPRenderer.parse(Data(xml.replacingOccurrences(of: "/control/av", with: "http://other.invalid/av").utf8), location: location) }
}
@Test func soapEscapesNestedMetadataAndPropagatesDeviceFault() throws {
    let data = UPnPSOAP.envelope(action: "SetAVTransportURI", service: "urn:schemas-upnp-org:service:AVTransport:1", arguments: [("CurrentURI", "http://192.168.1.2/video?a=1&b=2"), ("CurrentURIMetaData", "<title>A&B</title>")])
    let values = try UPnPSOAP.values(data)
    #expect(values["CurrentURI"] == "http://192.168.1.2/video?a=1&b=2")
    #expect(values["CurrentURIMetaData"] == "<title>A&B</title>")
    #expect(throws: (any Error).self) { try UPnPSOAP.values(Data("<Fault><errorCode>701</errorCode><errorDescription>Transition not available</errorDescription></Fault>".utf8)) }
    #expect(UPnPSOAP.seconds("01:02:03.5") == 3723.5)
    #expect(UPnPSOAP.seconds("NOT_IMPLEMENTED") == nil)
}

@Test func discoveryOnlyAllowsUnambiguousLocalIPv4WithoutEmbeddedCredentials() throws {
    for address in ["10.0.0.3", "172.16.4.5", "172.31.1.9", "192.168.1.3", "169.254.4.2"] {
        #expect(UPnPNetwork.isLocalIPv4(address))
    }
    for address in ["127.0.0.1", "172.15.1.3", "172.32.0.1", "8.8.8.8", "192.168.01.3", "192.168.1.256", "::1", "localhost", "192.168.1"] {
        #expect(!UPnPNetwork.isLocalIPv4(address))
    }
    #expect(throws: (any Error).self) { try UPnPNetwork.validate(URL(string: "http://user:secret@192.168.1.3/device.xml")!) }
}
