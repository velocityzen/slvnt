import Foundation

/// One entry in the player's catalog. The player returns extra fields; only the
/// three the client depends on are modeled (others decode away).
public struct Release: Sendable, Equatable, Codable, CustomStringConvertible {
    public var id: String?
    public var artist: String
    public var release: String

    public init(id: String? = nil, artist: String, release: String) {
        self.id = id
        self.artist = artist
        self.release = release
    }

    public var description: String {
        "\(artist) — \(release)" + (id.map { " [\($0)]" } ?? "")
    }
}
