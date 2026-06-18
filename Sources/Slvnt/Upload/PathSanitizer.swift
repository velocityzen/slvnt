import Foundation

/// Makes a local name safe for the player's FTP filesystem. Mirrors the
/// Manager's `sanitizePathSegment` exactly so remote paths line up with the
/// device's expectations.
public enum PathSanitizer {
    private static let illegal: Set<Character> = [
        "/", "\\", ":", "*", "?", "\"", "<", ">", "|", "\u{0}",
    ]
    private static let trimmed = CharacterSet.whitespacesAndNewlines.union(
        CharacterSet(charactersIn: "."))

    /// Sanitize one path segment (a folder or file name, never a full path).
    /// Illegal and control characters become `_`, runs of `_` collapse, leading
    /// and trailing whitespace/dots are stripped, and an empty result is `Unknown`.
    public static func sanitize(_ segment: String) -> String {
        var out = ""
        for character in segment {
            if illegal.contains(character) || isControl(character) {
                out.append("_")
            } else {
                out.append(character)
            }
        }
        while out.contains("__") {
            out = out.replacingOccurrences(of: "__", with: "_")
        }
        out = out.trimmingCharacters(in: trimmed)
        return out.isEmpty ? "Unknown" : out
    }

    private static func isControl(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first
        else {
            return false
        }
        return scalar.value <= 0x1F
    }
}
