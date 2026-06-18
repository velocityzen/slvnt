import Foundation

/// Storage usage reported by `GET /api/storage`.
public struct Storage: Sendable, Equatable, Codable, CustomStringConvertible {
    public var totalBytes: Int64
    public var usedBytes: Int64

    public init(totalBytes: Int64, usedBytes: Int64) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
    }

    public var freeBytes: Int64 { max(0, totalBytes - usedBytes) }

    public var usedPercent: Double {
        totalBytes > 0 ? 100 * Double(usedBytes) / Double(totalBytes) : 0
    }

    public var description: String {
        "\(Self.formatted(usedBytes)) / \(Self.formatted(totalBytes)) used"
            + " (\(String(format: "%.0f", usedPercent))%), \(Self.formatted(freeBytes)) free"
    }

    /// Human-readable, 1024-based byte size (e.g. "1.5 GB").
    public static func formatted(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unit = 0
        while size >= 1024, unit < units.count - 1 {
            size /= 1024
            unit += 1
        }
        return unit == 0 ? "\(bytes) B" : String(format: "%.1f %@", size, units[unit])
    }
}
