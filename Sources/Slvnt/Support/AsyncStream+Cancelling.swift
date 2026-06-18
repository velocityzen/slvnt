import Foundation

extension AsyncStream {
    /// Build a stream fed by an async `produce` closure that runs in its own task.
    ///
    /// The stream finishes when `produce` returns, and the producing task is
    /// cancelled if the consumer stops iterating early — so a blocked producer
    /// receives a cancellation signal instead of leaking. This centralizes the
    /// `Task` + `onTermination` + `finish()` wiring that's easy to get wrong.
    static func cancelling(
        _ produce: @escaping @Sendable (Continuation) async -> Void
    ) -> AsyncStream<Element> {
        AsyncStream { continuation in
            let task = Task {
                await produce(continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
