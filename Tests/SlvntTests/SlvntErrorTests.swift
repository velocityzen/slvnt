import Testing

@testable import Slvnt

@Suite("SlvntError.isTransportFailure")
struct SlvntErrorTests {
    @Test("only network failures are transport failures (they abort a batch)")
    func transportFailures() {
        #expect(SlvntError.network("connection reset").isTransportFailure)
    }

    @Test("per-item failures are not transport failures (the batch can skip them)")
    func perItemFailures() {
        #expect(!SlvntError.ftp("STOR /a/b.flac refused (550)").isTransportFailure)
        #expect(!SlvntError.io(path: "/a/b.flac", reason: "could not read file").isTransportFailure)
        #expect(!SlvntError.notFound("x").isTransportFailure)
        #expect(!SlvntError.invalidInput("x").isTransportFailure)
    }
}
