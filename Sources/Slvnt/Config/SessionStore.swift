import Foundation
import FP

/// Persists the paired `Session` (device + transfer code) between CLI runs.
public protocol SessionStore: Sendable {
    func load() -> Result<Session?, SlvntError>
    func save(_ session: Session) -> Result<Void, SlvntError>
    func clear() -> Result<Void, SlvntError>
}

/// Stores the session as JSON under `~/.config/slvnt/session.json`.
///
/// Note: the transfer code is the device's only credential and is written in
/// plaintext here (the official Manager likewise keeps it unencrypted). Treat
/// the file as a secret.
public struct FileSessionStore: SessionStore {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL()
    }

    public static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/slvnt", directoryHint: .isDirectory)
            .appending(path: "session.json")
    }

    public var path: String { fileURL.path }

    public func load() -> Result<Session?, SlvntError> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .success(nil)
        }

        return Result { try Data(contentsOf: fileURL) }
            .mapError { SlvntError.io(path: self.fileURL.path, reason: $0.localizedDescription) }
            .flatMap(Self.decode)
    }

    public func save(_ session: Session) -> Result<Void, SlvntError> {
        ensureDirectory()
            .flatMap { _ in Self.encode(session) }
            .flatMap(write)
    }

    public func clear() -> Result<Void, SlvntError> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .success(())
        }

        return Result { try FileManager.default.removeItem(at: fileURL) }
            .mapError {
                SlvntError.io(path: self.fileURL.path, reason: $0.localizedDescription)
            }
    }

    // MARK: - Steps

    private func ensureDirectory() -> Result<Void, SlvntError> {
        let directory = fileURL.deletingLastPathComponent()

        return Result {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }
        .mapError {
            SlvntError.io(path: directory.path, reason: $0.localizedDescription)
        }
    }

    private func write(_ data: Data) -> Result<Void, SlvntError> {
        Result { try data.write(to: fileURL, options: [.atomic]) }
            .mapError {
                SlvntError.io(path: self.fileURL.path, reason: $0.localizedDescription)
            }
    }

    private static func decode(_ data: Data) -> Result<Session?, SlvntError> {
        Result { try JSONDecoder().decode(Session.self, from: data) }
            .map { Optional($0) }
            .mapError { SlvntError.decoding($0.localizedDescription) }
    }

    private static func encode(_ session: Session) -> Result<Data, SlvntError> {
        Result { try JSONEncoder().encode(session) }
            .mapError { SlvntError.decoding($0.localizedDescription) }
    }
}
