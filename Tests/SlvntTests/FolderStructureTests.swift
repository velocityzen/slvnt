import Testing
@testable import Slvnt

@Suite("FolderStructure")
struct FolderStructureTests {
    @Test("tracks present, plain name → album level")
    func albumLevel() {
        #expect(
            FolderStructure.classify(
                name: "Album", hasUploadableFiles: true, hasSubdirectories: false) == .albumLevel
        )
    }

    @Test("tracks present, Artist - Album name → single level")
    func singleLevel() {
        #expect(
            FolderStructure.classify(
                name: "Aphex Twin - Drukqs", hasUploadableFiles: true, hasSubdirectories: false)
                == .singleLevel
        )
    }

    @Test("no tracks but subfolders → two level")
    func twoLevel() {
        #expect(
            FolderStructure.classify(
                name: "Music", hasUploadableFiles: false, hasSubdirectories: true) == .twoLevel
        )
    }

    @Test("empty folder defaults to album level")
    func empty() {
        #expect(
            FolderStructure.classify(
                name: "Empty", hasUploadableFiles: false, hasSubdirectories: false) == .albumLevel
        )
    }

    @Test("splitArtistAlbum splits on the first ' - '")
    func split() {
        let parts = splitArtistAlbum("Boards of Canada - Music Has the Right to Children")
        #expect(parts?.artist == "Boards of Canada")
        #expect(parts?.album == "Music Has the Right to Children")
        #expect(splitArtistAlbum("NoSeparator") == nil)
    }
}
