import FP
import FPBracket
import Foundation

/// A single FTP control connection to the player. The actor serializes access so
/// the underlying socket and reply buffer are never touched concurrently; each
/// call runs its blocking work on a dedicated thread via `BlockingIO`.
public actor FTPClient {
    private let fd: Int32
    private let host: String
    private let reader: ReplyReader

    private init(fd: Int32, host: String, reader: ReplyReader) {
        self.fd = fd
        self.host = host
        self.reader = reader
    }

    /// Connect and log in (`USER sleevenote` / `PASS <code>`, binary mode).
    public static func connect(
        host: String,
        port: Int,
        username: String = "sleevenote",
        password: String
    ) async -> Result<FTPClient, SlvntError> {
        await BlockingIO.run {
            FTPRaw.connect(host: host, port: port, username: username, password: password)
        }
        .map { FTPClient(fd: $0.fd, host: host, reader: $0.reader) }
    }

    /// A scoped FTP session: connect and log in on entry, `quit` on exit —
    /// always, even on failure. Run it with `await session { client in … }`.
    public static func session(
        host: String,
        port: Int,
        username: String = "sleevenote",
        password: String
    ) -> BracketAsync<FTPClient, SlvntError> {
        BracketAsync(
            acquire: {
                await Self.connect(host: host, port: port, username: username, password: password)
            },
            dispose: { client in
                await client.quit()
                return .success(())
            }
        )
    }

    /// Create `remoteDirectory` and any missing parents (idempotent).
    public func ensureDirectory(_ remoteDirectory: String) async -> Result<Void, SlvntError> {
        let fd = self.fd
        let reader = self.reader
        return await BlockingIO.run {
            FTPRaw.ensureDirectory(fd: fd, reader: reader, remoteDirectory: remoteDirectory)
        }
    }

    /// Store `data` at the absolute `remotePath` (parent directories must exist).
    public func store(remotePath: String, data: Data) async -> Result<Void, SlvntError> {
        let fd = self.fd
        let host = self.host
        let reader = self.reader
        return await BlockingIO.run {
            FTPRaw.store(fd: fd, host: host, reader: reader, remotePath: remotePath, data: data)
        }
    }

    /// Send `QUIT` and close the control connection. Safe to call once.
    public func quit() async {
        let fd = self.fd
        let reader = self.reader
        _ = await BlockingIO.run { FTPRaw.quit(fd: fd, reader: reader) }
    }
}
