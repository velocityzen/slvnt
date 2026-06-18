import Foundation

/// Opaque device descriptor from `GET /api/info`. The wire shape is not
/// constrained by the client, so it is carried as pretty-printed JSON for display.
public struct DeviceInfo: Sendable, Equatable, CustomStringConvertible {
    public var json: String

    public init(json: String) {
        self.json = json
    }

    public var description: String { json }
}
