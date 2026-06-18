import Foundation

/// One file to transfer: where it is locally and where it lands on the player.
public struct UploadItem: Sendable, Equatable {
    public var localPath: String
    /// Absolute remote path, e.g. `/Aphex Twin/Selected Ambient Works/01.flac`.
    public var remotePath: String
    public var sizeBytes: Int64

    public init(localPath: String, remotePath: String, sizeBytes: Int64) {
        self.localPath = localPath
        self.remotePath = remotePath
        self.sizeBytes = sizeBytes
    }
}

/// A resolved set of files to upload, plus the directories that must exist first.
public struct UploadPlan: Sendable, Equatable {
    public var items: [UploadItem]

    public init(items: [UploadItem]) {
        self.items = items
    }

    public var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Distinct remote parent directories, in first-seen order, to `MKD` before storing.
    public var remoteDirectories: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for item in items {
            let directory = (item.remotePath as NSString).deletingLastPathComponent
            if seen.insert(directory).inserted {
                ordered.append(directory)
            }
        }
        return ordered
    }
}
