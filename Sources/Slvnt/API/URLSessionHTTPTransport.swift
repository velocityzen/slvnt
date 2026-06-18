import Foundation
import FP
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `URLSession`-backed transport. Accepts the player's self-signed TLS
/// certificate on the HTTPS (`8443`) path — the device ships one and the
/// official Manager does the same (`rejectUnauthorized: false`).
public final class URLSessionHTTPTransport: NSObject, HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(allowSelfSigned: Bool = true) {
        let delegate = TrustDelegate(allowSelfSigned: allowSelfSigned)
        self.session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        super.init()
    }

    public func send(_ request: HTTPRequest) async -> Result<HTTPResponse, SlvntError> {
        await buildRequest(request)
            .flatMapAsync { urlRequest in
                await Result.fromAsync {
                    try await self.session.data(for: urlRequest)
                }
                .mapError { SlvntError.network($0.localizedDescription) }
                .flatMap(Self.toResponse)
            }
    }

    private func buildRequest(_ request: HTTPRequest) async -> Result<URLRequest, SlvntError> {
        guard let url = URL(string: request.url) else {
            return .failure(.invalidInput("bad URL: \(request.url)"))
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeout

        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }

        return .success(urlRequest)
    }

    private static func toResponse(_ pair: (Data, URLResponse)) -> Result<HTTPResponse, SlvntError>
    {
        guard let http = pair.1 as? HTTPURLResponse else {
            return .failure(.network("response was not HTTP"))
        }

        return .success(HTTPResponse(status: http.statusCode, body: pair.0))
    }
}

/// Trusts the server certificate for server-trust challenges when self-signed
/// certs are allowed; otherwise falls back to default validation.
private final class TrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let allowSelfSigned: Bool

    init(allowSelfSigned: Bool) {
        self.allowSelfSigned = allowSelfSigned
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            allowSelfSigned,
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
