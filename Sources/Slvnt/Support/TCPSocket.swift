import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Minimal blocking TCP client primitives for the FTP control/data channels.
/// Hosts must be numeric IPv4 (discovery yields IPs; PASV replies are numeric).
enum TCPSocket {
    static func connect(host: String, port: Int, receiveTimeout: TimeInterval = 600) -> Int32? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(truncatingIfNeeded: port).bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { close(fd); return nil }

        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { close(fd); return nil }

        var tv = timeval(tv_sec: Int(receiveTimeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }

    /// Write every byte; returns false on any short/failed write.
    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        guard !data.isEmpty else { return true }
        return data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            var sent = 0
            while sent < raw.count {
                let n = send(fd, base + sent, raw.count - sent, 0)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }

    /// Read whatever is currently available (up to `max`); nil on EOF/timeout/error.
    static func readAvailable(_ fd: Int32, max: Int = 8192) -> Data? {
        var buffer = [UInt8](repeating: 0, count: max)
        let n = recv(fd, &buffer, max, 0)
        guard n > 0 else { return nil }
        return Data(buffer.prefix(n))
    }
}
