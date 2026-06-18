import Foundation

/// Seam over the local filesystem so upload planning is testable with an
/// in-memory tree.
public protocol FileSystem: Sendable {
    func exists(_ path: String) -> Bool
    func isDirectory(_ path: String) -> Bool
    /// Immediate child names (not full paths), excluding `.`/`..`.
    func childrenNames(_ path: String) -> [String]
    func fileSize(_ path: String) -> Int64?
    func readFile(_ path: String) -> Data?
}

extension FileSystem {
    /// Immediate children of `path` as full paths, excluding hidden (dot-prefixed) entries.
    public func children(of path: String) -> [String] {
        childrenNames(path)
            .filter { !$0.hasPrefix(".") }
            .map { path + "/" + $0 }
    }

    /// The (non-hidden) subdirectories directly in `path`, as full paths.
    public func subdirectories(of path: String) -> [String] {
        children(of: path).filter { isDirectory($0) }
    }

    /// The (non-hidden) files — non-directories — directly in `path`, as full paths.
    public func files(in path: String) -> [String] {
        children(of: path).filter { !isDirectory($0) }
    }
}

public struct LocalFileSystem: FileSystem {
    public init() {}

    public func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    public func childrenNames(_ path: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    public func fileSize(_ path: String) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            let size = attributes[.size] as? NSNumber
        else { return nil }
        return size.int64Value
    }

    public func readFile(_ path: String) -> Data? {
        FileManager.default.contents(atPath: path)
    }
}
