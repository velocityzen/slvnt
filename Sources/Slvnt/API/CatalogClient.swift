import Foundation
import FP

/// Selects a release to remove — by id (preferred) or artist/release pair.
public enum ReleaseSelector: Sendable, Equatable {
    case id(String)
    case artistRelease(artist: String, release: String)

    var jsonBody: Data {
        let object: [String: String]
        switch self {
            case .id(let id):
                object = ["id": id]
            case .artistRelease(let artist, let release):
                object = ["artist": artist, "release": release]
        }
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}

/// The player's HTTP catalog & control API. Every call returns a typed `Result`;
/// `401`/`"invalid or missing transfer code"` collapses to `.unauthorized`.
public struct CatalogClient: Sendable {
    public static let codeHeader = "X-Sleevenote-Code"

    let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionHTTPTransport()) {
        self.transport = transport
    }

    /// `GET /api/info` — unauthenticated reachability/identity probe.
    public func info(device: Device) async -> Result<DeviceInfo, SlvntError> {
        await get(device: device, path: "/api/info", code: nil)
            .flatMap(Self.prettyInfo)
    }

    /// `GET /api/releases?q=` — the catalog, optionally filtered.
    public func releases(session: Session, search: String? = nil) async -> Result<
        [Release], SlvntError
    > {
        await get(device: session.device, path: releasesPath(search: search), code: session.code)
            .flatMap { Self.decode(ReleasesEnvelope.self, from: $0) }
            .map { $0.releases ?? [] }
    }

    /// `GET /api/storage`.
    public func storage(session: Session) async -> Result<Storage, SlvntError> {
        await get(device: session.device, path: "/api/storage", code: session.code)
            .flatMap { Self.decode(Storage.self, from: $0) }
    }

    /// `GET /api/battery`.
    public func battery(session: Session) async -> Result<Battery, SlvntError> {
        await get(device: session.device, path: "/api/battery", code: session.code)
            .flatMap { Self.decode(Battery.self, from: $0) }
    }

    /// `POST /api/releases/remove`.
    public func remove(session: Session, selector: ReleaseSelector) async -> Result<
        Void, SlvntError
    > {
        await post(
            device: session.device,
            path: "/api/releases/remove",
            code: session.code,
            body: selector.jsonBody,
            timeout: 60
        ).asUnit()
    }

    /// `POST /api/disconnect` — invalidates the session/transfer code.
    public func disconnect(session: Session) async -> Result<Void, SlvntError> {
        await post(device: session.device, path: "/api/disconnect", code: session.code, body: nil)
            .asUnit()
    }

    // MARK: - Request plumbing

    private func get(device: Device, path: String, code: String?) async -> Result<Data, SlvntError>
    {
        await send(
            HTTPRequest(method: .get, url: device.baseURL + path, headers: headers(code: code)))
    }

    private func post(
        device: Device,
        path: String,
        code: String?,
        body: Data?,
        timeout: TimeInterval = 30
    ) async -> Result<Data, SlvntError> {
        var headers = headers(code: code)
        if body != nil { headers["Content-Type"] = "application/json" }
        return await send(
            HTTPRequest(
                method: .post,
                url: device.baseURL + path,
                headers: headers,
                body: body,
                timeout: timeout
            ))
    }

    private func send(_ request: HTTPRequest) async -> Result<Data, SlvntError> {
        await transport.send(request).flatMap(Self.checkStatus)
    }

    private func headers(code: String?) -> [String: String] {
        guard let code, !code.isEmpty else { return [:] }
        return [Self.codeHeader: code]
    }

    private func releasesPath(search: String?) -> String {
        guard let term = search?.trimmingCharacters(in: .whitespacesAndNewlines), !term.isEmpty
        else {
            return "/api/releases"
        }
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "q", value: term)]
        return "/api/releases?" + (components.percentEncodedQuery ?? "")
    }

    // MARK: - Response handling

    private static func checkStatus(_ response: HTTPResponse) -> Result<Data, SlvntError> {
        if (200..<300).contains(response.status) {
            return .success(response.body)
        }
        let bodyText = String(data: response.body, encoding: .utf8) ?? ""
        if response.status == 401
            || bodyText.localizedCaseInsensitiveContains("invalid or missing transfer code")
        {
            return .failure(.unauthorized)
        }
        return .failure(.http(status: response.status, body: oneLine(bodyText)))
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> Result<
        T, SlvntError
    > {
        Result { try JSONDecoder().decode(type, from: data) }
            .mapError { .decoding($0.localizedDescription) }
    }

    private static func prettyInfo(_ data: Data) -> Result<DeviceInfo, SlvntError> {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: pretty, encoding: .utf8)
        else {
            return .success(DeviceInfo(json: String(data: data, encoding: .utf8) ?? ""))
        }
        return .success(DeviceInfo(json: text))
    }
}

private struct ReleasesEnvelope: Decodable {
    let releases: [Release]?
}

private func oneLine(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\n", with: " ")
}
