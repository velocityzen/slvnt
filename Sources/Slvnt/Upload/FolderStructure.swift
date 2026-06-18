import Foundation

/// How a local source folder is shaped, which decides how Artist/Album are derived.
/// Mirrors the Manager's `detectFolderStructurePath` classification.
public enum FolderStructure: String, Sendable, Equatable {
    /// Folder holds tracks directly and is *not* named `Artist - Album`.
    case albumLevel
    /// Folder holds tracks directly and *is* named `Artist - Album`.
    case singleLevel
    /// Folder holds no tracks directly but contains subfolders (artist → album…).
    case twoLevel

    /// Classify from three facts about the folder. Pure — the filesystem read
    /// happens at the call site, keeping this directly testable.
    public static func classify(
        name: String,
        hasUploadableFiles: Bool,
        hasSubdirectories: Bool
    ) -> FolderStructure {
        if hasUploadableFiles {
            return name.contains(" - ") ? .singleLevel : .albumLevel
        }
        if hasSubdirectories {
            return .twoLevel
        }
        return .albumLevel
    }
}

/// Split a `"Artist - Album"` folder name into its two parts. Returns nil when
/// there is no `" - "` separator.
public func splitArtistAlbum(_ name: String) -> (artist: String, album: String)? {
    guard let range = name.range(of: " - ") else { return nil }
    let artist = name[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
    let album = name[range.upperBound...].trimmingCharacters(in: .whitespaces)
    return (artist, album)
}
