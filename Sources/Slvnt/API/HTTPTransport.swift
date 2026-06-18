import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

public struct HTTPRequest: Sendable {
    public var method: HTTPMethod
    public var url: String
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval

    public init(
        method: HTTPMethod,
        url: String,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 30
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Seam over HTTP so the catalog client is testable without a live device.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async -> Result<HTTPResponse, SlvntError>
}
