import Foundation
import Testing

@testable import Slvnt

@Suite("BlockingIO")
struct BlockingIOTests {
    @Test("runCancellable surfaces task cancellation to the blocking closure")
    func observesCancellation() async {
        let task = Task {
            await BlockingIO.runCancellable { isCancelled in
                // Poll up to ~5s; return as soon as cancellation is observed.
                for _ in 0..<5000 {
                    if isCancelled() { return true }
                    Thread.sleep(forTimeInterval: 0.001)
                }
                return false
            }
        }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        #expect(await task.value)
    }

    @Test("run completes normally without cancellation")
    func runsToCompletion() async {
        let value = await BlockingIO.run { 21 + 21 }
        #expect(value == 42)
    }
}
