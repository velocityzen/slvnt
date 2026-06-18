import Foundation
import FP

/// Discovers a player and runs the transfer-code handshake.
///
/// `discover` races two mechanisms and returns whichever answers first:
/// mDNS (`_sleevenote._tcp`, usually fastest thanks to the OS resolver cache)
/// and UDP broadcast (`SLEEVENOTE_DISCOVERY` on :9999). Running both covers
/// networks that block one or the other.
public struct DiscoveryService: Sendable {
    public static let port: UInt16 = 9999
    public static let serviceType = "_sleevenote._tcp"
    static let discoveryMagic = Data("SLEEVENOTE_DISCOVERY".utf8)
    static let transferCodeMagic = Data("REQUEST_TRANSFER_CODE".utf8)

    let transport: DiscoveryTransport
    let browser: ServiceBrowser

    public init(
        transport: DiscoveryTransport = POSIXUDPTransport(),
        browser: ServiceBrowser = NWBrowserServiceBrowser()
    ) {
        self.transport = transport
        self.browser = browser
    }

    /// Find the first player that answers via mDNS or UDP broadcast. Whichever
    /// *succeeds* first wins; a fast failure on one path never beats a slower
    /// success on the other (see `withAny`).
    public func discover(timeout: Duration = .seconds(5)) async -> Result<Device, SlvntError> {
        await withAny(
            await self.discoverViaMDNS(timeout: timeout),
            await self.discoverViaBroadcast(timeout: timeout)
        )
    }

    func discoverViaMDNS(timeout: Duration) async -> Result<Device, SlvntError> {
        await browser
            .firstService(type: Self.serviceType, timeout: timeout)
            .map(Self.device(from:))
    }

    func discoverViaBroadcast(timeout: Duration) async -> Result<Device, SlvntError> {
        await transport
            .broadcast(Self.discoveryMagic, port: Self.port, timeout: timeout)
            .flatMap(Self.firstDevice)
    }

    /// Ask the player at `host` to show a fresh transfer code on its screen and
    /// acknowledge. Retries until `timeout`, since the UDP responder may come up
    /// shortly after the device is first seen.
    public func requestTransferCode(
        host: String,
        timeout: Duration = .seconds(8),
        attemptTimeout: Duration = .seconds(3)
    ) async -> Result<Void, SlvntError> {
        await withTimeout(timeout, failingWith: SlvntError.transferCodeRejected("no response")) {
            await self.requestCodeUntilReply(host: host, attemptTimeout: attemptTimeout)
        }
    }

    /// Re-send the UDP probe until the device replies. Its responder may come up
    /// shortly after discovery, and datagrams can be dropped — so a no-reply is
    /// retried, while any reply (an ack or an explicit rejection) is definitive.
    /// Loops until a reply arrives or `withTimeout` cancels it.
    private func requestCodeUntilReply(
        host: String,
        attemptTimeout: Duration
    ) async -> Result<Void, SlvntError> {
        while !Task.isCancelled {
            let reply = await transport.exchange(
                Self.transferCodeMagic,
                host: host,
                port: Self.port,
                timeout: attemptTimeout
            )

            if case .success(let data) = reply {
                return Self.checkAck(data)
            }
        }
        return .failure(.transferCodeRejected("no response"))
    }

    // MARK: - Helpers

    /// mDNS carries no FTP port, so it defaults to 2121 (per the API spec).
    static func device(from service: ResolvedService) -> Device {
        Device(
            name: service.name,
            ip: service.ip,
            httpPort: service.port,
            ftpPort: 2121,
            useHTTPS: service.port == 8443
        )
    }

    static func firstDevice(_ datagrams: [Datagram]) -> Result<Device, SlvntError> {
        let parsed = datagrams.map { DeviceDescriptor.parse($0.data) }
        return Result.fromOptional(parsed.successes().first, error: SlvntError.noDeviceFound)
    }

    static func checkAck(_ data: Data) -> Result<Void, SlvntError> {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .success(())
        }
        let status = object["status"] as? String
        if status == nil || status == "success" {
            return .success(())
        }
        return .failure(.transferCodeRejected(object["message"] as? String ?? "request failed"))
    }
}
