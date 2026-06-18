import Foundation

/// Pure parsing of the FTP control-channel replies the client needs to read.
/// Kept separate from the socket I/O so it can be unit-tested directly.
public enum FTPReply {
    /// The leading 3-digit status code of a reply line, if the line starts with one.
    public static func code(of line: String) -> Int? {
        let head = line.prefix(3)
        guard head.count == 3, head.allSatisfy({ $0 >= "0" && $0 <= "9" }) else {
            return nil
        }

        return Int(head)
    }

    /// A reply line is the *final* line of a (possibly multi-line) reply when its
    /// 3-digit code is followed by a space, not a hyphen (RFC 959).
    public static func isFinal(_ line: String) -> Bool {
        guard code(of: line) != nil else {
            return false
        }

        let fourth = line.dropFirst(3).first
        return fourth == " " || fourth == nil
    }

    /// Parse the data host/port from a PASV reply:
    /// `227 Entering Passive Mode (h1,h2,h3,h4,p1,p2)`.
    public static func parsePASV(_ line: String) -> (host: String, port: Int)? {
        guard
            let open = line.firstIndex(of: "("),
            let close = line[open...].firstIndex(of: ")"),
            open < close
        else {
            return nil
        }

        let inside = line[line.index(after: open)..<close]
        let parts = inside.split(separator: ",").map {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
        let numbers = parts.compactMap { $0 }
        guard numbers.count == 6, numbers.allSatisfy({ (0...255).contains($0) }) else {
            return nil
        }

        let host = "\(numbers[0]).\(numbers[1]).\(numbers[2]).\(numbers[3])"
        let port = numbers[4] * 256 + numbers[5]
        return (host, port)
    }
}
