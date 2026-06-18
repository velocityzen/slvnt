import Foundation

/// A paired session: the device plus the 4-digit transfer code that authorizes
/// every catalog request (HTTP header) and FTP login (password).
public struct Session: Sendable, Equatable, Codable, CustomStringConvertible {
    public var device: Device
    public var code: String

    public init(device: Device, code: String) {
        self.device = device
        self.code = code
    }

    public var description: String {
        "\(device.name) (\(device.ip)) — code \(code)"
    }
}
