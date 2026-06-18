import Foundation

/// Builds an `UploadPlan` from a local file or folder, mirroring the Manager's
/// structure detection and `/Artist/Album/file` layout. Pure given its seams
/// (`FileSystem`, `MetadataReader`), so it is directly testable.
public struct UploadPlanner: Sendable {
    let fileSystem: FileSystem
    let metadata: MetadataReader

    public init(
        fileSystem: FileSystem = LocalFileSystem(), metadata: MetadataReader = NoMetadataReader()
    ) {
        self.fileSystem = fileSystem
        self.metadata = metadata
    }

    public func plan(forPath path: String) -> Result<UploadPlan, SlvntError> {
        guard fileSystem.exists(path) else {
            return .failure(.notFound(path))
        }

        return fileSystem.isDirectory(path) ? planDirectory(path) : planFile(path)
    }

    // MARK: - File

    private func planFile(_ path: String) -> Result<UploadPlan, SlvntError> {
        if MediaKind.isHidden(path) {
            return .failure(.invalidInput("hidden files cannot be transferred"))
        }

        guard MediaKind.isUploadable(path) else {
            return .failure(.invalidInput("file type is not transferable: \(lastComponent(path))"))
        }

        let filename = lastComponent(path)
        let stem = (filename as NSString).deletingPathExtension
        let (artist, album) =
            metadata.artistAlbum(forFile: path) ?? ("Unknown", stem.isEmpty ? "Unknown" : stem)
        let base = [PathSanitizer.sanitize(artist), PathSanitizer.sanitize(album)]
        let remote = "/" + (base + [PathSanitizer.sanitize(filename)]).joined(separator: "/")

        let item = UploadItem(
            localPath: path,
            remotePath: remote,
            sizeBytes: fileSystem.fileSize(path) ?? 0
        )
        return .success(UploadPlan(items: [item]))
    }

    // MARK: - Directory

    private func planDirectory(_ path: String) -> Result<UploadPlan, SlvntError> {
        let name = lastComponent(path)
        let structure = FolderStructure.classify(
            name: name,
            hasUploadableFiles: hasUploadableFiles(path),
            hasSubdirectories: !fileSystem.subdirectories(of: path).isEmpty
        )
        switch structure {
            case .albumLevel:
                let fallbackArtist = nonEmpty(lastComponent(parent(path))) ?? "Unknown"
                return .success(
                    planRelease(
                        dir: path,
                        fallbackArtist: fallbackArtist,
                        fallbackAlbum: name
                    )
                )

            case .singleLevel:
                let (artist, album) = splitArtistAlbum(name) ?? ("Unknown", name)
                return .success(
                    planRelease(
                        dir: path,
                        fallbackArtist: artist,
                        fallbackAlbum: album
                    )
                )
            case .twoLevel:
                return .success(
                    planTwoLevel(
                        container: path,
                        containerArtist: nonEmpty(name) ?? "Unknown"
                    )
                )
        }
    }

    private func planRelease(dir: String, fallbackArtist: String, fallbackAlbum: String)
        -> UploadPlan
    {
        UploadPlan(
            items: releaseItems(
                dir: dir,
                fallbackArtist: fallbackArtist,
                fallbackAlbum: fallbackAlbum
            )
        )
    }

    private func planTwoLevel(container: String, containerArtist: String) -> UploadPlan {
        let items = twoLevelTargets(container: container, containerArtist: containerArtist)
            .flatMap {
                releaseItems(dir: $0.dir, fallbackArtist: $0.artist, fallbackAlbum: $0.album)
            }

        return UploadPlan(items: items)
    }

    /// The upload items for one release directory: Artist/Album resolved (tags,
    /// else the fallbacks) and sanitized into the remote-path root.
    private func releaseItems(dir: String, fallbackArtist: String, fallbackAlbum: String)
        -> [UploadItem]
    {
        let (artist, album) = resolveRelease(
            dir: dir,
            fallbackArtist: fallbackArtist,
            fallbackAlbum: fallbackAlbum
        )
        let base = [PathSanitizer.sanitize(artist), PathSanitizer.sanitize(album)]
        return collectFiles(dir: dir, baseSegments: base, relative: [])
    }

    /// Album folders under a two-level container. A subdir with no files but its
    /// own subdirs is treated as an artist whose children are albums.
    private func twoLevelTargets(
        container: String,
        containerArtist: String
    ) -> [(dir: String, artist: String, album: String)] {
        fileSystem.subdirectories(of: container).flatMap {
            subdir -> [(dir: String, artist: String, album: String)] in
            guard !hasUploadableFiles(subdir), !fileSystem.subdirectories(of: subdir).isEmpty else {
                // Holds tracks directly: an album under the container artist.
                return [(subdir, containerArtist, lastComponent(subdir))]
            }
            // An artist folder: its subdirs are that artist's albums.
            let artist = nonEmpty(lastComponent(subdir)) ?? containerArtist

            return fileSystem.subdirectories(of: subdir).map {
                (dir: $0, artist: artist, album: lastComponent($0))
            }
        }
    }

    // MARK: - Walking & metadata

    private func resolveRelease(dir: String, fallbackArtist: String, fallbackAlbum: String) -> (
        artist: String, album: String
    ) {
        if let audio = firstAudioFile(dir), let tags = metadata.artistAlbum(forFile: audio) {
            return tags
        }
        return (fallbackArtist, fallbackAlbum)
    }

    private func collectFiles(dir: String, baseSegments: [String], relative: [String])
        -> [UploadItem]
    {
        let here = uploadableFiles(dir).map { file -> UploadItem in
            let segments =
                baseSegments + (relative + [lastComponent(file)]).map(PathSanitizer.sanitize)

            return UploadItem(
                localPath: file,
                remotePath: "/" + segments.joined(separator: "/"),
                sizeBytes: fileSystem.fileSize(file) ?? 0
            )
        }

        let nested = fileSystem.subdirectories(of: dir).flatMap { subdir in
            collectFiles(
                dir: subdir, baseSegments: baseSegments,
                relative: relative + [lastComponent(subdir)]
            )
        }

        return here + nested
    }

    private func firstAudioFile(_ dir: String) -> String? {
        fileSystem.files(in: dir).first(where: MediaKind.isAudio)
            ?? fileSystem.subdirectories(of: dir).lazy.compactMap(firstAudioFile).first
    }

    private func hasUploadableFiles(_ dir: String) -> Bool {
        !uploadableFiles(dir).isEmpty
    }

    /// The uploadable (audio or artwork) files directly in `dir`.
    private func uploadableFiles(_ dir: String) -> [String] {
        fileSystem.files(in: dir).filter(MediaKind.isUploadable)
    }

    private func lastComponent(_ path: String) -> String { (path as NSString).lastPathComponent }
    private func parent(_ path: String) -> String { (path as NSString).deletingLastPathComponent }
    private func nonEmpty(_ value: String) -> String? { value.isEmpty ? nil : value }
}
