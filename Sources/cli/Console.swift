import Foundation

/// Small output helpers for the CLI.
enum Console {
    /// Write a prompt to stderr (keeping stdout clean) and read a line from stdin.
    static func prompt(_ message: String) -> String {
        FileHandle.standardError.write(Data(message.utf8))
        return readLine(strippingNewline: true) ?? ""
    }

    /// Write a transient status line to stderr.
    static func status(_ message: String) {
        FileHandle.standardError.write(Data(message.utf8))
    }
}
