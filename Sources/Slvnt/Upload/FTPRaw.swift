import FP
import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Buffers the FTP control channel and hands back one complete reply at a time.
/// Used only from within `FTPClient`'s actor isolation (one call in flight), so
/// the mutable buffer is never touched concurrently.
final class ReplyReader: @unchecked Sendable {
    private let fd: Int32
    private var buffer = Data()

    init(fd: Int32) { self.fd = fd }

    /// The next complete reply, reading more from the socket as needed.
    func next() -> Result<(code: Int, text: String), SlvntError> {
        while true {
            if let reply = takeBufferedReply() { return .success(reply) }
            guard let chunk = TCPSocket.readAvailable(fd) else {
                // The socket is gone — a transport failure, not an FTP-level reply.
                return .failure(.network("control connection closed while awaiting a reply"))
            }
            buffer.append(chunk)
        }
    }

    func expect(_ code: Int, context: String) -> Result<Int, SlvntError> {
        next().flatMap { reply in
            reply.code == code
                ? .success(reply.code)
                : .failure(
                    .ftp(
                        "expected \(code) at \(context), got \(reply.code): \(oneLine(reply.text))")
                )
        }
    }

    private func takeBufferedReply() -> (code: Int, text: String)? {
        guard let text = String(data: buffer, encoding: .utf8), text.contains("\r\n") else {
            return nil
        }
        let lines = text.components(separatedBy: "\r\n")
        for index in 0..<(lines.count - 1) where FTPReply.isFinal(lines[index]) {
            let consumed = lines[0...index].joined(separator: "\r\n") + "\r\n"
            buffer.removeFirst(min(consumed.utf8.count, buffer.count))
            return (FTPReply.code(of: lines[index]) ?? 0, consumed)
        }
        return nil
    }
}

/// The raw FTP exchanges the client needs: login, ensure-directory, store, quit.
///
/// Socket-level failures (connect/write/read) surface as `.network` — the
/// transport is gone. FTP negative replies (the server answered, but with an
/// error code) surface as `.ftp` — the connection is alive; that command/file
/// was rejected. The upload loop relies on this split to skip a rejected file
/// while aborting on a lost connection.
enum FTPRaw {
    static func connect(
        host: String,
        port: Int,
        username: String,
        password: String
    ) -> Result<(fd: Int32, reader: ReplyReader), SlvntError> {
        guard let fd = TCPSocket.connect(host: host, port: port) else {
            return .failure(.network("could not connect to \(host):\(port)"))
        }
        let reader = ReplyReader(fd: fd)
        return reader.expect(220, context: "greeting")
            .flatMap { _ in command(fd, reader, "USER \(username)", expect: [230, 331]) }
            .flatMap { _ in command(fd, reader, "PASS \(password)", expect: [230, 202, 200]) }
            .flatMap { _ in command(fd, reader, "TYPE I", expect: [200]) }
            .map { _ in (fd, reader) }
            .tapError { _ in close(fd) }
    }

    static func ensureDirectory(fd: Int32, reader: ReplyReader, remoteDirectory: String) -> Result<
        Void, SlvntError
    > {
        var path = ""
        for segment in remoteDirectory.split(separator: "/").filter({ !$0.isEmpty }) {
            path += "/" + segment
            // 257 = created, 550/521 = already exists — both acceptable.
            guard TCPSocket.writeAll(fd, line("MKD \(path)")) else {
                return .failure(.network("failed to send MKD \(path)"))
            }
            if case .failure(let error) = reader.next() { return .failure(error) }
        }
        return .success(())
    }

    static func store(fd: Int32, host: String, reader: ReplyReader, remotePath: String, data: Data)
        -> Result<Void, SlvntError>
    {
        passiveDataPort(fd: fd, reader: reader)
            .flatMap { port -> Result<Int32, SlvntError> in
                // Behind NAT the PASV-reported IP can be unroutable; reuse the control host.
                guard let dataFD = TCPSocket.connect(host: host, port: port) else {
                    return .failure(.network("could not open data connection to \(host):\(port)"))
                }
                return .success(dataFD)
            }
            .flatMap { dataFD in
                transfer(fd: fd, dataFD: dataFD, reader: reader, remotePath: remotePath, data: data)
            }
    }

    static func quit(fd: Int32, reader: ReplyReader) -> Result<Void, SlvntError> {
        _ = TCPSocket.writeAll(fd, line("QUIT"))
        _ = reader.next()
        close(fd)
        return .success(())
    }

    // MARK: - Helpers

    private static func passiveDataPort(fd: Int32, reader: ReplyReader) -> Result<Int, SlvntError> {
        guard TCPSocket.writeAll(fd, line("PASV")) else {
            return .failure(.network("failed to send PASV"))
        }
        return reader.next().flatMap { reply in
            guard reply.code == 227, let pasv = FTPReply.parsePASV(reply.text) else {
                return .failure(.ftp("bad PASV reply: \(oneLine(reply.text))"))
            }
            return .success(pasv.port)
        }
    }

    /// Sends STOR, streams the bytes, and closes the data connection exactly once
    /// (before reading the completion reply, so the server sees EOF).
    private static func transfer(
        fd: Int32, dataFD: Int32, reader: ReplyReader, remotePath: String, data: Data
    ) -> Result<Void, SlvntError> {
        guard TCPSocket.writeAll(fd, line("STOR \(remotePath)")) else {
            close(dataFD)
            return .failure(.network("failed to send STOR \(remotePath)"))
        }
        switch reader.next() {
            case .failure(let error):
                close(dataFD)
                return .failure(error)
            case .success(let reply) where reply.code != 150 && reply.code != 125:
                close(dataFD)
                return .failure(
                    .ftp("STOR \(remotePath) refused (\(reply.code)): \(oneLine(reply.text))"))
            case .success:
                break
        }
        let wrote = TCPSocket.writeAll(dataFD, data)
        close(dataFD)
        guard wrote else { return .failure(.network("data write failed for \(remotePath)")) }
        return reader.next().flatMap { reply in
            (200..<300).contains(reply.code)
                ? .success(())
                : .failure(
                    .ftp(
                        "transfer of \(remotePath) not acknowledged (\(reply.code)): \(oneLine(reply.text))"
                    ))
        }
    }

    private static func command(
        _ fd: Int32, _ reader: ReplyReader, _ text: String, expect: Set<Int>
    ) -> Result<Int, SlvntError> {
        guard TCPSocket.writeAll(fd, line(text)) else {
            return .failure(.network("failed to send: \(commandName(text))"))
        }
        return reader.next().flatMap { reply in
            expect.contains(reply.code)
                ? .success(reply.code)
                : .failure(
                    .ftp(
                        "unexpected reply \(reply.code) to \(commandName(text)): \(oneLine(reply.text))"
                    ))
        }
    }

    private static func line(_ text: String) -> Data { Data((text + "\r\n").utf8) }
    private static func commandName(_ text: String) -> String {
        String(text.split(separator: " ").first ?? "")
    }
}

private func oneLine(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\r\n", with: " ")
}
