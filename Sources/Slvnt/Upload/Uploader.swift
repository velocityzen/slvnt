import Foundation
import FP
import FPBracket
import FPPipe

/// One progress event, emitted as each file finishes transferring. The consumer
/// (CLI/UI) iterates the upload `Pipe` and renders these however it likes.
public struct UploadEvent: Sendable, Equatable {
    public var fileName: String
    /// 1-based position of this file in the upload.
    public var fileIndex: Int
    public var fileCount: Int
    /// Cumulative bytes transferred through this file (precomputed, not counted live).
    public var transferredBytes: Int64
    public var totalBytes: Int64

    public init(
        fileName: String, fileIndex: Int, fileCount: Int, transferredBytes: Int64, totalBytes: Int64
    ) {
        self.fileName = fileName
        self.fileIndex = fileIndex
        self.fileCount = fileCount
        self.transferredBytes = transferredBytes
        self.totalBytes = totalBytes
    }

    public var fraction: Double {
        totalBytes > 0 ? min(1, Double(transferredBytes) / Double(totalBytes)) : 0
    }
}

/// Plans a local path and streams it to the player over FTP as a `Pipe` of
/// `UploadEvent`s. The pipe is lazy and re-iterable: each iteration opens its own
/// FTP connection (owned by a `BracketAsync`, so it's always closed), transfers
/// the files in order, and emits one event per completed file. There is no
/// progress callback or shared counter — progress lives in the events.
public struct Uploader: Sendable {
    let planner: UploadPlanner

    public init(planner: UploadPlanner = UploadPlanner()) {
        self.planner = planner
    }

    /// A pipe that uploads the file or folder at `localPath` when iterated. Each
    /// element is one file's outcome — `.success(UploadEvent)`, or `.failure` for
    /// a file that was unreadable or rejected by the player (the batch keeps
    /// going). A transport failure (lost connection) ends the stream early.
    public func upload(localPath: String, to session: Session)
        -> FPPipe.Pipe<UploadEvent, SlvntError>
    {
        switch planner.plan(forPath: localPath) {
            case .failure(let error):
                FPPipe.Pipe<UploadEvent, SlvntError> {
                    Failure(error, valueType: UploadEvent.self)
                }

            case .success(let plan) where plan.items.isEmpty:
                FPPipe.Pipe<UploadEvent, SlvntError> {
                    Failure(
                        SlvntError.notFound("no uploadable files under \(localPath)"),
                        valueType: UploadEvent.self
                    )
                }

            case .success(let plan):
                FPPipe.Pipe<UploadEvent, SlvntError> {
                    DeferResult { self.eventStream(plan: plan, session: session) }
                }
        }
    }

    // MARK: - Streaming source

    /// A fresh single-shot stream of upload events, backed by one FTP connection.
    private func eventStream(plan: UploadPlan, session: Session) -> AsyncStream<
        Result<UploadEvent, SlvntError>
    > {
        let device = session.device
        let code = session.code
        let fileSystem = planner.fileSystem
        let entries = Self.entries(for: plan)
        let total = plan.totalBytes
        let directories = plan.remoteDirectories

        return .cancelling { continuation in
            let withFTP = FTPClient.session(
                host: device.ip,
                port: device.ftpPort,
                password: code
            )

            let outcome = await withFTP { client in
                await Self.ensureDirectories(directories, on: client)
                    .flatMapAsync { _ -> Result<Void, SlvntError> in
                        for entry in entries {
                            if Task.isCancelled { break }

                            let event = await Self.storeOne(
                                entry,
                                on: client,
                                fileCount: entries.count,
                                total: total,
                                fileSystem: fileSystem
                            )

                            continuation.yield(event)
                            // A per-file failure (unreadable / rejected by the player)
                            // is reported, but the batch keeps going. Only a lost
                            // connection aborts the rest.
                            if case .failure(let error) = event, error.isTransportFailure {
                                break
                            }
                        }
                        return .success(())
                    }
            }

            // Surface a setup failure (connect / directory creation); per-file
            // failures were already yielded inside the loop.
            if case .failure(let error) = outcome {
                continuation.failure(error)
            }
        }
    }

    private static func ensureDirectories(
        _ directories: [String], on client: FTPClient
    ) async -> Result<Void, SlvntError> {
        await directories
            .traverseAsync { await client.ensureDirectory($0) }
            .asUnit()
    }

    /// Read one file and store it, mapping success to its `UploadEvent`. A pure
    /// `Result` flow — no stream, no continuation.
    private static func storeOne(
        _ entry: UploadEntry,
        on client: FTPClient,
        fileCount: Int,
        total: Int64,
        fileSystem: FileSystem
    ) async -> Result<UploadEvent, SlvntError> {
        await Result.fromOptional(
            fileSystem.readFile(entry.item.localPath),
            error: SlvntError.io(path: entry.item.localPath, reason: "could not read file")
        )
        .flatMapAsync { data in await client.store(remotePath: entry.item.remotePath, data: data) }
        .map { _ in
            UploadEvent(
                fileName: (entry.item.localPath as NSString).lastPathComponent,
                fileIndex: entry.index,
                fileCount: fileCount,
                transferredBytes: entry.cumulativeBytes,
                totalBytes: total
            )
        }
    }

    /// Pair each item with its 1-based index and cumulative byte total — a pure
    /// prefix sum, so progress needs no live counter.
    static func entries(for plan: UploadPlan) -> [UploadEntry] {
        var cumulative: Int64 = 0

        return plan.items.enumerated().map { index, item in
            cumulative += item.sizeBytes
            return UploadEntry(item: item, index: index + 1, cumulativeBytes: cumulative)
        }
    }
}

/// An upload item annotated with its position and cumulative byte total.
struct UploadEntry: Sendable, Equatable {
    let item: UploadItem
    let index: Int
    let cumulativeBytes: Int64
}
