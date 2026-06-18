import ArgumentParser
import Foundation
import FPPipe
import Slvnt

struct Upload: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Upload a file or folder of music to the player."
    )

    @OptionGroup var connection: ConnectionOptions

    @Argument(help: "Files or folders to upload.")
    var paths: [String] = []

    func validate() throws {
        guard !paths.isEmpty else {
            throw ValidationError("Provide at least one file or folder to upload.")
        }
        for path in paths where !FileManager.default.fileExists(atPath: path) {
            throw ValidationError("Path does not exist: \(path)")
        }
    }

    func run() async throws {
        let session = try connection.resolveSession().get()
        let uploader = Uploader()
        var uploaded = 0
        var failures: [SlvntError] = []

        for path in paths {
            print("Uploading \(path) → \(session.device.name)…")
            let result = await transfer(uploader.upload(localPath: path, to: session))
            uploaded += result.uploaded
            failures += result.failures
        }

        let summary =
            failures.isEmpty
            ? "Done. \(uploaded) file\(uploaded == 1 ? "" : "s") uploaded."
            : "Done. \(uploaded) uploaded, \(failures.count) failed."
        print(summary)
        if !failures.isEmpty { throw ExitCode.failure }
    }

    /// Drive one upload pipe: render progress, and collect per-file failures
    /// (which don't stop the batch). Returns the tally for this path.
    private func transfer(
        _ pipe: FPPipe.Pipe<UploadEvent, SlvntError>
    ) async -> (uploaded: Int, failures: [SlvntError]) {
        var uploaded = 0
        var failures: [SlvntError] = []
        for await element in pipe {
            switch element {
                case .success(let event):
                    uploaded += 1
                    let percent = Int(event.fraction * 100)
                    Console.status(
                        "\r  [\(event.fileIndex)/\(event.fileCount) \(percent)%] \(event.fileName)\u{1B}[K"
                    )
                case .failure(let error):
                    failures.append(error)
                    // Persist the failure on its own line; progress resumes below it.
                    Console.status("\r  ✗ \(error.localizedDescription)\u{1B}[K\n")
            }
        }
        Console.status("\r\u{1B}[K")
        return (uploaded, failures)
    }
}
