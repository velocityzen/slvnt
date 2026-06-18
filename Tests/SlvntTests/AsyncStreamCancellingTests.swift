import Testing

@testable import Slvnt

@Suite("AsyncStream.cancelling")
struct AsyncStreamCancellingTests {
    @Test("yields produced values, then finishes when the producer returns")
    func producesAndFinishes() async {
        let stream = AsyncStream<Int>.cancelling { continuation in
            continuation.yield(1)
            continuation.yield(2)
            continuation.yield(3)
        }

        var collected: [Int] = []
        for await value in stream {
            collected.append(value)
        }
        #expect(collected == [1, 2, 3])
    }
}
