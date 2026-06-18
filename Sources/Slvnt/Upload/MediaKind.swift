import Foundation

/// The file types the player accepts, and the extension test the client applies
/// before uploading anything (everything else is skipped).
public enum MediaKind {
    public static let audioExtensions: Set<String> = ["mp3", "flac", "m4a", "wav", "aac", "ogg"]
    public static let artworkExtensions: Set<String> = ["jpg", "jpeg", "png", "webp"]

    /// True when `path`'s extension is an uploadable audio or artwork type.
    public static func isUploadable(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return audioExtensions.contains(ext) || artworkExtensions.contains(ext)
    }

    /// True when `path`'s extension is a supported audio type (not artwork).
    public static func isAudio(_ path: String) -> Bool {
        audioExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// Dot-files are never transferred (mirrors the Manager's hidden-file skip).
    public static func isHidden(_ path: String) -> Bool {
        (path as NSString).lastPathComponent.hasPrefix(".")
    }
}
