import ArgumentParser
import Foundation
import FP
import Slvnt

/// Shared flags for talking to a player: either use the saved session or
/// override it with an explicit host/port/code for a one-off command.
struct ConnectionOptions: ParsableArguments {
    @Option(name: .long, help: "Player IP address (skips the saved session).")
    var host: String?

    @Option(name: .long, help: "HTTP API port (default 8080; 8443 implies HTTPS).")
    var httpPort: Int?

    @Option(name: .long, help: "FTP port (default 2121).")
    var ftpPort: Int?

    @Flag(name: .long, help: "Use HTTPS for the catalog API.")
    var https: Bool = false

    @Option(name: .long, help: "4-digit transfer code (overrides the saved one).")
    var code: String?

    @Option(name: .long, help: "Session file (default ~/.config/slvnt/session.json).")
    var config: String?

    var store: FileSessionStore {
        FileSessionStore(fileURL: config.map { URL(filePath: $0) })
    }

    /// Build a `Device` from explicit flags (used when `--host` is given).
    private func deviceFromFlags(host: String) -> Device {
        let port = httpPort ?? 8080

        return Device(
            name: host,
            ip: host,
            httpPort: port,
            ftpPort: ftpPort ?? 2121,
            useHTTPS: https || port == 8443
        )
    }

    /// Resolve a full session (device + code) for authenticated commands.
    func resolveSession() -> Result<Session, SlvntError> {
        store.load().flatMap { saved in
            guard let host else {
                return Result.fromOptional(saved, error: SlvntError.noSession)
                    .map { session in
                        code.map { Session(device: session.device, code: $0) } ?? session
                    }
            }

            return Result.fromOptional(
                code ?? saved?.code,
                error: SlvntError.invalidInput("no transfer code — pass --code or run `slvnt pair`")
            )
            .map { Session(device: deviceFromFlags(host: host), code: $0) }
        }
    }

    /// Resolve just a device (for `info` and `pair`, which need no transfer code).
    func resolveDevice() -> Result<Device, SlvntError> {
        if let host {
            return .success(deviceFromFlags(host: host))
        }

        return store.load().flatMap { saved in
            Result.fromOptional(saved?.device, error: SlvntError.noSession)
        }
    }
}
