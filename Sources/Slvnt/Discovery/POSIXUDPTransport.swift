import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// `DiscoveryTransport` backed by BSD UDP sockets. Blocking calls run on a
/// dedicated thread (see `BlockingIO`) so they never block the cooperative pool.
public struct POSIXUDPTransport: DiscoveryTransport {
    public init() {}

    public func broadcast(
        _ payload: Data,
        port: UInt16,
        timeout: Duration
    ) async -> Result<[Datagram], SlvntError> {
        await BlockingIO.runCancellable { isCancelled in
            Self.broadcastSync(payload, port: port, timeout: timeout, isCancelled: isCancelled)
        }
    }

    public func exchange(
        _ payload: Data,
        host: String,
        port: UInt16,
        timeout: Duration
    ) async -> Result<Data, SlvntError> {
        await BlockingIO.run {
            Self.exchangeSync(payload, host: host, port: port, timeout: timeout)
        }
    }

    // MARK: - Blocking socket work

    private static func broadcastSync(
        _ payload: Data,
        port: UInt16,
        timeout: Duration,
        isCancelled: @Sendable () -> Bool
    ) -> Result<[Datagram], SlvntError> {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return .failure(.network("socket() failed")) }
        defer { close(fd) }

        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        setReceiveTimeout(fd, milliseconds: 400)

        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0
        local.sin_addr.s_addr = 0
        let bound = withUnsafePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return .failure(.network("bind() failed")) }

        var targets = Set(broadcastAddresses())
        targets.insert("255.255.255.255")
        for target in targets {
            sendDatagram(fd, payload, host: target, port: port)
        }

        // Early-exit on the first reply: the device is the only responder to the
        // discovery magic on :9999, so there's no reason to wait the full window.
        var datagrams: [Datagram] = []
        let deadline = Date().addingTimeInterval(timeout.timeInterval)
        while Date() < deadline {
            // Bail promptly when the task is cancelled (e.g. mDNS won the race).
            // The receive timeout bounds how long until the next check (~400ms).
            if isCancelled() { break }
            if let datagram = receiveDatagram(fd) {
                datagrams.append(datagram)
                break
            }
        }
        return .success(datagrams)
    }

    private static func exchangeSync(
        _ payload: Data,
        host: String,
        port: UInt16,
        timeout: Duration
    ) -> Result<Data, SlvntError> {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return .failure(.network("socket() failed")) }
        defer { close(fd) }
        setReceiveTimeout(fd, milliseconds: Int(timeout.timeInterval * 1000))
        sendDatagram(fd, payload, host: host, port: port)
        if let datagram = receiveDatagram(fd) {
            return .success(datagram.data)
        }
        return .failure(.network("no reply from \(host):\(port)"))
    }

    // MARK: - Primitives

    private static func setReceiveTimeout(_ fd: Int32, milliseconds: Int) {
        let clamped = max(1, milliseconds)
        var tv = timeval(tv_sec: clamped / 1000, tv_usec: Int32((clamped % 1000) * 1000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func makeAddress(host: String, port: UInt16) -> sockaddr_in? {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        return inet_pton(AF_INET, host, &addr.sin_addr) == 1 ? addr : nil
    }

    private static func sendDatagram(_ fd: Int32, _ data: Data, host: String, port: UInt16) {
        guard var addr = makeAddress(host: host, port: port) else { return }
        _ = data.withUnsafeBytes { raw in
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(
                        fd, raw.baseAddress, raw.count, 0, $0,
                        socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private static func receiveDatagram(_ fd: Int32, maxBytes: Int = 8192) -> Datagram? {
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        var buffer = [UInt8](repeating: 0, count: maxBytes)
        let received = buffer.withUnsafeMutableBytes { raw in
            withUnsafeMutablePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, raw.baseAddress, maxBytes, 0, $0, &length)
                }
            }
        }
        guard received > 0 else { return nil }
        return Datagram(data: Data(buffer.prefix(received)), sourceIP: ipString(from: &storage))
    }

    private static func ipString(from storage: inout sockaddr_storage) -> String {
        var addr = withUnsafePointer(to: &storage) {
            $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
        }
        return ipString(&addr)
    }

    private static func ipString(_ addr: inout in_addr) -> String {
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
            return ""
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Subnet broadcast address of every up, non-loopback, broadcast-capable IPv4 interface.
    private static func broadcastAddresses() -> [String] {
        var addresses: [String] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return addresses }
        defer { freeifaddrs(list) }

        var cursor = list
        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }
            let flags = Int32(interface.pointee.ifa_flags)
            guard
                (flags & IFF_UP) != 0,
                (flags & IFF_LOOPBACK) == 0,
                (flags & IFF_BROADCAST) != 0,
                let rawAddr = interface.pointee.ifa_addr,
                rawAddr.pointee.sa_family == sa_family_t(AF_INET),
                let rawMask = interface.pointee.ifa_netmask
            else { continue }

            let address = rawAddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr.s_addr
            }
            let mask = rawMask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr.s_addr
            }
            var broadcast = in_addr(s_addr: address | ~mask)
            addresses.append(ipString(&broadcast))
        }
        return addresses
    }
}
