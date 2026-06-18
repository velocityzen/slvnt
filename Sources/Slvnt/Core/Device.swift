import Foundation

/// A Sleevenote player discovered on the network.
public struct Device: Sendable, Equatable, Codable, CustomStringConvertible {
    public var name: String
    public var ip: String
    public var httpPort: Int
    public var ftpPort: Int
    public var useHTTPS: Bool

    public init(name: String, ip: String, httpPort: Int, ftpPort: Int, useHTTPS: Bool) {
        self.name = name
        self.ip = ip
        self.httpPort = httpPort
        self.ftpPort = ftpPort
        self.useHTTPS = useHTTPS
    }

    /// `http(s)://<ip>:<httpPort>` — the catalog API root.
    public var baseURL: String {
        "\(useHTTPS ? "https" : "http")://\(ip):\(httpPort)"
    }

    public var description: String {
        "\(name) (\(ip)) — HTTP \(httpPort)\(useHTTPS ? " TLS" : ""), FTP \(ftpPort)"
    }
}
