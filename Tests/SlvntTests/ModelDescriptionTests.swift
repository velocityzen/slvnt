import Testing
@testable import Slvnt

@Suite("Model descriptions")
struct ModelDescriptionTests {
    @Test("Release shows artist — release, with id when present")
    func release() {
        #expect(
            Release(id: "a1", artist: "Aphex Twin", release: "Drukqs").description
                == "Aphex Twin — Drukqs [a1]")
        #expect(
            Release(artist: "Boards of Canada", release: "Geogaddi").description
                == "Boards of Canada — Geogaddi")
    }

    @Test("Device summarizes name, ip, and ports")
    func device() {
        let device = Device(
            name: "SN", ip: "10.0.0.5", httpPort: 8443, ftpPort: 2121, useHTTPS: true)
        #expect(device.description == "SN (10.0.0.5) — HTTP 8443 TLS, FTP 2121")
    }

    @Test("Storage formats sizes and percent")
    func storage() {
        let gib: Int64 = 1024 * 1024 * 1024
        let storage = Storage(totalBytes: 64 * gib, usedBytes: 16 * gib)
        #expect(storage.description == "16.0 GB / 64.0 GB used (25%), 48.0 GB free")
    }

    @Test("Battery notes charging state")
    func battery() {
        #expect(Battery(chargePercent: 82, charging: true).description == "82% (charging)")
        #expect(Battery(chargePercent: 82, charging: false).description == "82%")
    }
}
