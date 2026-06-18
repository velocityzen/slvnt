import Foundation

/// Battery state reported by `GET /api/battery`.
public struct Battery: Sendable, Equatable, Codable, CustomStringConvertible {
    public var chargePercent: Int
    public var charging: Bool

    public init(chargePercent: Int, charging: Bool) {
        self.chargePercent = chargePercent
        self.charging = charging
    }

    public var description: String {
        "\(chargePercent)%" + (charging ? " (charging)" : "")
    }
}
