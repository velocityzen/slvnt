import Foundation
import Testing
import FP
@testable import Slvnt

@Suite("UploadPlanner")
struct UploadPlannerTests {
    private func planner(_ nodes: [String: FakeFileSystem.Node]) -> UploadPlanner {
        UploadPlanner(fileSystem: FakeFileSystem(nodes: nodes))
    }

    @Test("single file falls back to Unknown/<stem>")
    func singleFile() throws {
        let plan = try planner([
            "/music/track.flac": .file(size: 100, data: Data())
        ]).plan(forPath: "/music/track.flac").get()
        #expect(
            plan.items == [
                UploadItem(
                    localPath: "/music/track.flac", remotePath: "/Unknown/track/track.flac",
                    sizeBytes: 100)
            ])
    }

    @Test("non-audio/art file is rejected")
    func rejectsUnsupported() {
        let result = planner([
            "/music/notes.txt": .file(size: 10, data: Data())
        ]).plan(forPath: "/music/notes.txt")
        #expect(throws: SlvntError.self) { try result.get() }
    }

    @Test("album-level folder uses parent as artist and skips hidden/non-media")
    func albumLevel() throws {
        let plan = try planner([
            "/abc/Some Album": .directory([
                "01.flac", "02.flac", "cover.jpg", ".hidden", "notes.txt",
            ]),
            "/abc/Some Album/01.flac": .file(size: 10, data: Data()),
            "/abc/Some Album/02.flac": .file(size: 20, data: Data()),
            "/abc/Some Album/cover.jpg": .file(size: 5, data: Data()),
            "/abc/Some Album/.hidden": .file(size: 1, data: Data()),
            "/abc/Some Album/notes.txt": .file(size: 1, data: Data()),
        ]).plan(forPath: "/abc/Some Album").get()
        #expect(plan.items.count == 3)
        #expect(plan.totalBytes == 35)
        #expect(plan.remoteDirectories == ["/abc/Some Album"])
        #expect(
            plan.items.map(\.remotePath).sorted() == [
                "/abc/Some Album/01.flac",
                "/abc/Some Album/02.flac",
                "/abc/Some Album/cover.jpg",
            ])
    }

    @Test("single-level folder splits Artist - Album")
    func singleLevel() throws {
        let plan = try planner([
            "/x/Aphex Twin - Drukqs": .directory(["01.flac"]),
            "/x/Aphex Twin - Drukqs/01.flac": .file(size: 10, data: Data()),
        ]).plan(forPath: "/x/Aphex Twin - Drukqs").get()
        #expect(plan.items.map(\.remotePath) == ["/Aphex Twin/Drukqs/01.flac"])
    }

    @Test("two-level library expands artists and albums")
    func twoLevel() throws {
        let plan = try planner([
            "/lib": .directory(["Artist A", "Artist B"]),
            "/lib/Artist A": .directory(["Album 1"]),
            "/lib/Artist A/Album 1": .directory(["01.flac"]),
            "/lib/Artist A/Album 1/01.flac": .file(size: 10, data: Data()),
            "/lib/Artist B": .directory(["02.mp3"]),
            "/lib/Artist B/02.mp3": .file(size: 20, data: Data()),
        ]).plan(forPath: "/lib").get()
        #expect(
            plan.items.map(\.remotePath).sorted() == [
                "/Artist A/Album 1/01.flac",
                "/lib/Artist B/02.mp3",
            ])
    }

    @Test("illegal characters in names are sanitized in remote paths")
    func sanitizes() throws {
        let plan = try planner([
            "/x/AC:DC - Back": .directory(["track*1.flac"]),
            "/x/AC:DC - Back/track*1.flac": .file(size: 10, data: Data()),
        ]).plan(forPath: "/x/AC:DC - Back").get()
        #expect(plan.items.map(\.remotePath) == ["/AC_DC/Back/track_1.flac"])
    }
}
