import Foundation
import Testing
import FP
@testable import Slvnt

@Suite("DeviceDescriptor")
struct DeviceDescriptorTests {
    private func parse(_ json: String) -> Result<Device, SlvntError> {
        DeviceDescriptor.parse(Data(json.utf8))
    }

    @Test("current schema with http_port and ftp_port")
    func current() throws {
        let device = try parse(
            #"{"hostname":"Sleevenote","ip":"192.168.1.42","http_port":8080,"ftp_port":2121}"#
        ).get()
        #expect(device.name == "Sleevenote")
        #expect(device.ip == "192.168.1.42")
        #expect(device.httpPort == 8080)
        #expect(device.ftpPort == 2121)
        #expect(device.useHTTPS == false)
    }

    @Test("http_port 8443 implies HTTPS")
    func https() throws {
        let device = try parse(#"{"device":"SN","ip":"10.0.0.5","http_port":8443}"#).get()
        #expect(device.useHTTPS)
        #expect(device.baseURL == "https://10.0.0.5:8443")
        #expect(device.ftpPort == 2121)  // defaulted
    }

    @Test("legacy schema with ip and port")
    func legacy() throws {
        let device = try parse(#"{"device":"Old","ip":"10.0.0.9","port":8080,"ssl":false}"#).get()
        #expect(device.httpPort == 8080)
        #expect(device.useHTTPS == false)
    }

    @Test("friendly name drops the mDNS suffix")
    func friendlyName() throws {
        let device = try parse(#"{"hostname":"Sleevenote.local","ip":"10.0.0.1","http_port":8080}"#)
            .get()
        #expect(device.name == "Sleevenote")
    }

    @Test("missing ip is rejected")
    func missingIP() {
        #expect(throws: SlvntError.self) {
            try parse(#"{"hostname":"x","http_port":8080}"#).get()
        }
    }
}
