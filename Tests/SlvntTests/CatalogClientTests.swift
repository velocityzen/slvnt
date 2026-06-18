import Foundation
import Testing
import FP
@testable import Slvnt

@Suite("CatalogClient")
struct CatalogClientTests {
    private let session = Session(
        device: Device(
            name: "SN", ip: "192.168.1.7", httpPort: 8080, ftpPort: 2121, useHTTPS: false),
        code: "1234"
    )

    @Test("releases parses the envelope and sends the code header")
    func releases() async throws {
        let recorder = RequestRecorder()
        let transport = FakeHTTPTransport.ok(
            #"{"releases":[{"id":"a1","artist":"Aphex Twin","release":"Drukqs"}]}"#,
            recorder: recorder
        )
        let releases = try await CatalogClient(transport: transport).releases(session: session)
            .get()
        #expect(releases == [Release(id: "a1", artist: "Aphex Twin", release: "Drukqs")])
        #expect(recorder.last?.url == "http://192.168.1.7:8080/api/releases")
        #expect(recorder.last?.headers[CatalogClient.codeHeader] == "1234")
    }

    @Test("search adds an encoded q parameter")
    func search() async throws {
        let recorder = RequestRecorder()
        let transport = FakeHTTPTransport.ok(#"{"releases":[]}"#, recorder: recorder)
        _ = try await CatalogClient(transport: transport).releases(
            session: session, search: "aphex twin"
        ).get()
        #expect(recorder.last?.url.contains("q=aphex%20twin") == true)
    }

    @Test("storage decodes and computes used percent")
    func storage() async throws {
        let transport = FakeHTTPTransport.ok(#"{"totalBytes":64000000000,"usedBytes":16000000000}"#)
        let storage = try await CatalogClient(transport: transport).storage(session: session).get()
        #expect(storage.totalBytes == 64_000_000_000)
        #expect(storage.usedPercent == 25)
        #expect(storage.freeBytes == 48_000_000_000)
    }

    @Test("battery decodes")
    func battery() async throws {
        let transport = FakeHTTPTransport.ok(#"{"chargePercent":82,"charging":true}"#)
        let battery = try await CatalogClient(transport: transport).battery(session: session).get()
        #expect(battery == Battery(chargePercent: 82, charging: true))
    }

    @Test("401 with the known body maps to unauthorized")
    func unauthorized() async {
        let transport = FakeHTTPTransport { _ in
            .success(
                HTTPResponse(
                    status: 401, body: Data(#"{"error":"invalid or missing transfer code"}"#.utf8)))
        }
        let result = await CatalogClient(transport: transport).releases(session: session)
        #expect(result == .failure(.unauthorized))
    }

    @Test("info is unauthenticated and pretty-printed")
    func info() async throws {
        let recorder = RequestRecorder()
        let transport = FakeHTTPTransport.ok(
            #"{"name":"Sleevenote","version":"1.2.3"}"#, recorder: recorder)
        let info = try await CatalogClient(transport: transport).info(device: session.device).get()
        #expect(info.json.contains("\"version\""))
        #expect(recorder.last?.url == "http://192.168.1.7:8080/api/info")
        #expect(recorder.last?.headers[CatalogClient.codeHeader] == nil)
    }

    @Test("remove by id posts an id body with JSON content type")
    func removeById() async throws {
        let recorder = RequestRecorder()
        let transport = FakeHTTPTransport(recorder: recorder) { _ in
            .success(HTTPResponse(status: 200, body: Data()))
        }
        try await CatalogClient(transport: transport).remove(session: session, selector: .id("a1"))
            .get()
        let body = try #require(recorder.last?.body)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: String]
        #expect(object == ["id": "a1"])
        #expect(recorder.last?.url == "http://192.168.1.7:8080/api/releases/remove")
        #expect(recorder.last?.headers["Content-Type"] == "application/json")
    }

    @Test("remove by artist/release posts both fields")
    func removeByPair() async throws {
        let recorder = RequestRecorder()
        let transport = FakeHTTPTransport(recorder: recorder) { _ in
            .success(HTTPResponse(status: 204, body: Data()))
        }
        try await CatalogClient(transport: transport)
            .remove(session: session, selector: .artistRelease(artist: "A", release: "B")).get()
        let body = try #require(recorder.last?.body)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: String]
        #expect(object == ["artist": "A", "release": "B"])
    }
}
