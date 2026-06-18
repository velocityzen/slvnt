import Foundation
import Testing
import FP
@testable import Slvnt

@Suite("DiscoveryService")
struct DiscoveryServiceTests {
    /// mDNS browser that never finds anything, so the broadcast path drives the test.
    private let noMDNS = FakeServiceBrowser(result: .failure(.noDeviceFound))

    @Test("broadcast: returns the first datagram that parses to a device")
    func firstValid() async throws {
        let junk = Datagram(data: Data("not json".utf8), sourceIP: "0.0.0.0")
        let valid = Datagram(
            data: Data(#"{"hostname":"SN","ip":"192.168.1.7","http_port":8080}"#.utf8),
            sourceIP: "192.168.1.7"
        )
        let transport = FakeDiscoveryTransport(broadcastResult: .success([junk, valid]))
        let device = try await DiscoveryService(transport: transport, browser: noMDNS)
            .discover(timeout: .seconds(1)).get()
        #expect(device.ip == "192.168.1.7")
    }

    @Test("both mechanisms find nothing yields noDeviceFound")
    func nothing() async {
        let transport = FakeDiscoveryTransport(broadcastResult: .success([]))
        let result = await DiscoveryService(transport: transport, browser: noMDNS)
            .discover(timeout: .milliseconds(10))
        #expect(result == .failure(.noDeviceFound))
    }

    @Test("mDNS: builds a device from the resolved service (FTP defaults to 2121)")
    func mdnsResolves() async throws {
        // broadcast finds nothing
        let transport = FakeDiscoveryTransport(broadcastResult: .success([]))
        let browser = FakeServiceBrowser(
            result: .success(ResolvedService(name: "Sleevenote", ip: "10.0.0.5", port: 8080)))
        let device = try await DiscoveryService(transport: transport, browser: browser)
            .discover(timeout: .seconds(1)).get()
        #expect(device.ip == "10.0.0.5")
        #expect(device.httpPort == 8080)
        #expect(device.ftpPort == 2121)
        #expect(device.useHTTPS == false)
    }

    @Test("mDNS: port 8443 yields an HTTPS device")
    func mdnsHTTPS() async throws {
        let browser = FakeServiceBrowser(
            result: .success(ResolvedService(name: "SN", ip: "10.0.0.6", port: 8443)))
        let device = try await DiscoveryService(
            transport: FakeDiscoveryTransport(broadcastResult: .success([])), browser: browser
        )
        .discover(timeout: .seconds(1)).get()
        #expect(device.useHTTPS)
        #expect(device.baseURL == "https://10.0.0.6:8443")
    }

    @Test("race: a fast broadcast wins over a slow mDNS")
    func raceBroadcastWins() async throws {
        let valid = Datagram(
            data: Data(#"{"hostname":"SN","ip":"192.168.1.9","http_port":8080}"#.utf8),
            sourceIP: "192.168.1.9"
        )
        let transport = FakeDiscoveryTransport(broadcastResult: .success([valid]))
        let slowMDNS = FakeServiceBrowser(
            result: .success(ResolvedService(name: "SN", ip: "10.0.0.9", port: 8080)),
            delay: .seconds(2)
        )
        let device = try await DiscoveryService(transport: transport, browser: slowMDNS)
            .discover(timeout: .seconds(5)).get()
        #expect(device.ip == "192.168.1.9")
    }

    @Test("transfer-code acknowledgement succeeds")
    func ack() async throws {
        let transport = FakeDiscoveryTransport(
            exchangeResult: .success(Data(#"{"status":"success"}"#.utf8)))
        try await DiscoveryService(transport: transport)
            .requestTransferCode(host: "1.2.3.4", timeout: .milliseconds(200)).get()
    }

    @Test("transfer-code rejection surfaces the message")
    func reject() async {
        let transport = FakeDiscoveryTransport(
            exchangeResult: .success(Data(#"{"status":"error","message":"busy"}"#.utf8))
        )
        let result = await DiscoveryService(transport: transport)
            .requestTransferCode(host: "1.2.3.4", timeout: .milliseconds(60))
        #expect(throws: SlvntError.transferCodeRejected("busy")) { try result.get() }
    }
}
