import Foundation

/// Reads `(artist, album)` from an audio file's tags. The planner falls back to
/// folder names when this returns `nil`.
///
/// The default `NoMetadataReader` always returns `nil` (so paths derive from
/// folder names, matching the Manager's *fallback* behavior). Tag reading
/// (ID3/FLAC/MP4) is a future implementation behind this same seam.
public protocol MetadataReader: Sendable {
    func artistAlbum(forFile path: String) -> (artist: String, album: String)?
}

public struct NoMetadataReader: MetadataReader {
    public init() {}
    public func artistAlbum(forFile path: String) -> (artist: String, album: String)? { nil }
}
