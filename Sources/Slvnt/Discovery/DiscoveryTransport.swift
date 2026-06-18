import Foundation

/// A UDP datagram received during discovery.
public struct Datagram: Sendable, Equatable {
    public let data: Data
    public let sourceIP: String

    public init(data: Data, sourceIP: String) {
        self.data = data
        self.sourceIP = sourceIP
    }
}

/// Seam over UDP so the discovery logic is testable without real sockets.
public protocol DiscoveryTransport: Sendable {
    /// Broadcast `payload` on `port` (subnet broadcasts + 255.255.255.255) and
    /// collect every datagram that arrives within `timeout`.
    func broadcast(
        _ payload: Data,
        port: UInt16,
        timeout: Duration
    ) async -> Result<[Datagram], SlvntError>

    /// Send `payload` to `host:port` and await a single reply within `timeout`.
    func exchange(
        _ payload: Data,
        host: String,
        port: UInt16,
        timeout: Duration
    ) async -> Result<Data, SlvntError>
}

extension Duration {
    /// Seconds as a `TimeInterval`, for bridging to POSIX/Foundation timeouts.
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
