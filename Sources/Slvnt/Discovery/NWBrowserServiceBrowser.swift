import Foundation
import Network

/// `ServiceBrowser` backed by Network framework's `NWBrowser`. Browses for the
/// Bonjour service and resolves the first instance to an IPv4 host/port by
/// opening a short-lived connection and reading its resolved path.
public struct NWBrowserServiceBrowser: ServiceBrowser {
    public init() {}

    public func firstService(type: String, timeout: Duration) async -> Result<
        ResolvedService, SlvntError
    > {
        await BonjourResolve().run(type: type, timeoutSeconds: timeout.timeInterval)
    }
}

/// Drives one browse-then-resolve cycle. All `NWBrowser`/`NWConnection`
/// callbacks fire on `queue` (serial), so the mutable state is confined to a
/// single executor — hence `@unchecked Sendable`.
private final class BonjourResolve: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.sleevenote.slvnt.mdns")
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var continuation: CheckedContinuation<Result<ResolvedService, SlvntError>, Never>?
    private var finished = false
    private var resolving = false

    func run(type: String, timeoutSeconds: TimeInterval) async -> Result<
        ResolvedService, SlvntError
    > {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async {
                    self.begin(
                        type: type, timeoutSeconds: timeoutSeconds, continuation: continuation)
                }
            }
        } onCancel: {
            // Lost the race (or caller cancelled): tear down the browser and
            // resume promptly instead of waiting out the timeout.
            queue.async { self.finishWithFailure(.noDeviceFound) }
        }
    }

    private func begin(
        type: String,
        timeoutSeconds: TimeInterval,
        continuation: CheckedContinuation<Result<ResolvedService, SlvntError>, Never>
    ) {
        // Already cancelled before we started: resume now, don't open a browser.
        guard !finished else {
            continuation.resume(returning: .failure(.noDeviceFound))
            return
        }
        self.continuation = continuation
        queue.asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
            self?.finishWithFailure(.noDeviceFound)
        }

        let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.finishWithFailure(.discoveryFailed("mDNS browse failed: \(error)"))
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.handle(results)
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    private func handle(_ results: Set<NWBrowser.Result>) {
        guard !finished, !resolving else { return }
        for result in results {
            if case .service = result.endpoint {
                resolving = true
                resolve(result.endpoint)
                return
            }
        }
    }

    private func resolve(_ endpoint: NWEndpoint) {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4  // FTP upload needs a numeric IPv4 address.
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
                case .ready:
                    self?.completeFromPath(of: connection, endpoint: endpoint)
                case .failed, .cancelled:
                    self?.resolving = false
                    connection.cancel()
                default:
                    break
            }
        }
        connection.start(queue: queue)
    }

    private func completeFromPath(of connection: NWConnection, endpoint: NWEndpoint) {
        defer { connection.cancel() }
        guard
            case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint,
            let ip = Self.ipv4(host)
        else {
            resolving = false
            return
        }

        finishWithSuccess(
            ResolvedService(
                name: Self.name(of: endpoint),
                ip: ip,
                port: Int(port.rawValue)
            )
        )
    }

    private func finishWithSuccess(_ service: ResolvedService) {
        finish(.success(service))
    }

    private func finishWithFailure(_ error: SlvntError) {
        finish(.failure(error))
    }

    /// Resume the continuation at most once and tear everything down.
    private func finish(_ result: Result<ResolvedService, SlvntError>) {
        guard !finished else {
            return
        }

        finished = true
        browser?.cancel()
        connection?.cancel()
        continuation?.resume(returning: result)
        continuation = nil
    }

    private static func ipv4(_ host: NWEndpoint.Host) -> String? {
        guard case .ipv4(let address) = host else {
            return nil
        }

        let bytes = address.rawValue
        guard bytes.count == 4 else {
            return nil
        }

        return "\(bytes[0]).\(bytes[1]).\(bytes[2]).\(bytes[3])"
    }

    private static func name(of endpoint: NWEndpoint) -> String {
        if case .service(let name, _, _, _) = endpoint, !name.isEmpty {
            return name
        }

        return "Sleevenote"
    }
}
