import Foundation
@testable import Slvnt

/// HTTP transport that answers from a closure and records every request.
struct FakeHTTPTransport: HTTPTransport {
    let recorder: RequestRecorder
    let handler: @Sendable (HTTPRequest) -> Result<HTTPResponse, SlvntError>

    init(
        recorder: RequestRecorder = RequestRecorder(),
        handler: @escaping @Sendable (HTTPRequest) -> Result<HTTPResponse, SlvntError>
    ) {
        self.recorder = recorder
        self.handler = handler
    }

    func send(_ request: HTTPRequest) async -> Result<HTTPResponse, SlvntError> {
        recorder.record(request)
        return handler(request)
    }

    /// Convenience: always answer 200 with `json`.
    static func ok(_ json: String, recorder: RequestRecorder = RequestRecorder())
        -> FakeHTTPTransport
    {
        FakeHTTPTransport(recorder: recorder) { _ in
            .success(HTTPResponse(status: 200, body: Data(json.utf8)))
        }
    }
}

/// Captures requests so tests can assert on URLs, headers, and bodies.
/// Tests run sequentially, so unsynchronized access is safe.
final class RequestRecorder: @unchecked Sendable {
    private(set) var requests: [HTTPRequest] = []
    var last: HTTPRequest? { requests.last }
    func record(_ request: HTTPRequest) { requests.append(request) }
}

/// Discovery transport with canned broadcast/exchange outcomes.
struct FakeDiscoveryTransport: DiscoveryTransport {
    var broadcastResult: Result<[Datagram], SlvntError> = .success([])
    var exchangeResult: Result<Data, SlvntError> = .failure(.network("no fake reply"))

    func broadcast(_ payload: Data, port: UInt16, timeout: Duration) async -> Result<
        [Datagram], SlvntError
    > {
        broadcastResult
    }

    func exchange(_ payload: Data, host: String, port: UInt16, timeout: Duration) async -> Result<
        Data, SlvntError
    > {
        exchangeResult
    }
}

/// Service browser with a canned outcome and optional delay (to drive races).
struct FakeServiceBrowser: ServiceBrowser {
    var result: Result<ResolvedService, SlvntError> = .failure(.noDeviceFound)
    var delay: Duration? = nil

    func firstService(type: String, timeout: Duration) async -> Result<ResolvedService, SlvntError>
    {
        if let delay { try? await Task.sleep(for: delay) }
        return result
    }
}

/// In-memory filesystem for upload-planner tests.
struct FakeFileSystem: FileSystem {
    enum Node: Sendable {
        case directory([String])
        case file(size: Int64, data: Data)
    }

    var nodes: [String: Node]

    func exists(_ path: String) -> Bool { nodes[path] != nil }

    func isDirectory(_ path: String) -> Bool {
        if case .directory = nodes[path] { return true }
        return false
    }

    func childrenNames(_ path: String) -> [String] {
        if case .directory(let names) = nodes[path] {
            return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        return []
    }

    func fileSize(_ path: String) -> Int64? {
        if case .file(let size, _) = nodes[path] { return size }
        return nil
    }

    func readFile(_ path: String) -> Data? {
        if case .file(_, let data) = nodes[path] { return data }
        return nil
    }
}
