import Testing
@testable import Slvnt

@Suite("Uploader.entries")
struct UploaderTests {
    @Test("annotates items with 1-based index and cumulative bytes (no live counter)")
    func cumulative() {
        let plan = UploadPlan(items: [
            UploadItem(localPath: "/a/1.flac", remotePath: "/A/B/1.flac", sizeBytes: 10),
            UploadItem(localPath: "/a/2.flac", remotePath: "/A/B/2.flac", sizeBytes: 20),
            UploadItem(localPath: "/a/3.flac", remotePath: "/A/B/3.flac", sizeBytes: 30),
        ])
        let entries = Uploader.entries(for: plan)
        #expect(entries.map(\.index) == [1, 2, 3])
        #expect(entries.map(\.cumulativeBytes) == [10, 30, 60])
        #expect(entries.last?.cumulativeBytes == plan.totalBytes)
    }

    @Test("empty plan yields no entries")
    func empty() {
        #expect(Uploader.entries(for: UploadPlan(items: [])).isEmpty)
    }
}
