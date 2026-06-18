import Foundation

/// A resolved mDNS/DNS-SD service instance: name plus a concrete IPv4 host and port.
public struct ResolvedService: Sendable, Equatable {
    public let name: String
    public let ip: String
    public let port: Int

    public init(name: String, ip: String, port: Int) {
        self.name = name
        self.ip = ip
        self.port = port
    }
}

/// Seam over Bonjour browsing so discovery is testable without the network.
public protocol ServiceBrowser: Sendable {
    /// Browse for `type` (e.g. `_sleevenote._tcp`) and resolve the first instance
    /// to an IPv4 host/port, within `timeout`.
    func firstService(type: String, timeout: Duration) async -> Result<ResolvedService, SlvntError>
}
