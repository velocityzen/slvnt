import Foundation

/// Every failure in slvnt travels in this typed channel instead of being thrown.
///
/// Cases map to the boundaries the player exposes: discovery (UDP), pairing
/// (transfer code), the HTTP catalog API, and FTP upload.
public enum SlvntError: LocalizedError, Sendable, Equatable, CustomStringConvertible {
    case noDeviceFound
    case discoveryFailed(String)
    case invalidDescriptor(String)
    case transferCodeRejected(String)
    case invalidTransferCode(String)
    case network(String)
    case http(status: Int, body: String)
    case unauthorized
    case decoding(String)
    case notFound(String)
    case ftp(String)
    case io(path: String, reason: String)
    case invalidInput(String)
    case noSession

    public var errorDescription: String? {
        switch self {
            case .noDeviceFound:
                "No Sleevenote player found on the local network."
            case .discoveryFailed(let reason):
                "Discovery failed: \(reason)"
            case .invalidDescriptor(let reason):
                "Could not read the device descriptor: \(reason)"
            case .transferCodeRejected(let reason):
                "The player rejected the transfer-code request: \(reason)"
            case .invalidTransferCode(let code):
                "Not a valid 4-digit transfer code: \"\(code)\""
            case .network(let reason):
                "Network error: \(reason)"
            case .http(let status, let body):
                "Player returned HTTP \(status): \(body)"
            case .unauthorized:
                "Invalid or missing transfer code — re-pair with `slvnt pair`."
            case .decoding(let reason):
                "Could not decode the player response: \(reason)"
            case .notFound(let what):
                "Not found: \(what)"
            case .ftp(let reason):
                "FTP transfer failed: \(reason)"
            case .io(let path, let reason):
                "I/O failure at \(path): \(reason)"
            case .invalidInput(let reason):
                "Invalid input: \(reason)"
            case .noSession:
                "Not paired with any player. Run `slvnt pair` first."
        }
    }

    /// Same human-readable message as `errorDescription`, so `print(error)` and
    /// string interpolation render the friendly text rather than the enum case.
    public var description: String {
        errorDescription ?? "slvnt error"
    }

    /// A transport-level failure: the network connection itself is gone (socket
    /// closed, or a write/read/connect error). An in-progress batch can't
    /// continue past this. A single item that's unreadable (`io`) or rejected by
    /// the player (`ftp`) is *not* a transport failure — the caller can skip it
    /// and keep going.
    public var isTransportFailure: Bool {
        if case .network = self { return true }
        return false
    }
}
