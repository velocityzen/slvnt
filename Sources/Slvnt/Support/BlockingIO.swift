import Foundation

/// Runs blocking POSIX socket work on a dedicated thread so it never starves the
/// Swift cooperative thread pool. The closure owns short-lived file descriptors;
/// nothing it touches escapes, so `@Sendable` is safe.
enum BlockingIO {
    /// Run blocking work that can't be interrupted (e.g. a bounded FTP exchange).
    static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            let thread = Thread { continuation.resume(returning: work()) }
            thread.stackSize = 1 << 20
            thread.start()
        }
    }

    /// Run blocking work that polls `isCancelled` to bail out early. When the
    /// surrounding task is cancelled, the probe flips to `true`, so a loop can
    /// stop on its next check — turning task cancellation into prompt teardown.
    static func runCancellable<T: Sendable>(
        _ work: @escaping @Sendable (_ isCancelled: @Sendable () -> Bool) -> T
    ) async -> T {
        let flag = CancellationFlag()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
                let thread = Thread { continuation.resume(returning: work(flag.isCancelled)) }
                thread.stackSize = 1 << 20
                thread.start()
            }
        } onCancel: {
            flag.markCancelled()
        }
    }
}

/// A thread-safe one-way flag flipped when the surrounding task is cancelled.
private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    /// A `@Sendable` probe to hand to the blocking closure.
    var isCancelled: @Sendable () -> Bool {
        { self.lock.withLock { self.cancelled } }
    }

    func markCancelled() {
        lock.withLock { cancelled = true }
    }
}
