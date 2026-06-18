import Testing
@testable import Slvnt

@Suite("FTPReply")
struct FTPReplyTests {
    @Test("reads the leading status code")
    func code() {
        #expect(FTPReply.code(of: "220 Welcome") == 220)
        #expect(FTPReply.code(of: "vsftpd") == nil)
    }

    @Test("distinguishes final lines from continuation lines")
    func final() {
        #expect(FTPReply.isFinal("226 Transfer complete"))
        #expect(!FTPReply.isFinal("226-First line of many"))
        #expect(!FTPReply.isFinal("hello"))
    }

    @Test("parses a PASV host and port")
    func pasv() {
        let parsed = FTPReply.parsePASV("227 Entering Passive Mode (192,168,1,42,195,80)")
        #expect(parsed?.host == "192.168.1.42")
        #expect(parsed?.port == 195 * 256 + 80)
    }

    @Test("rejects malformed PASV replies")
    func badPasv() {
        #expect(FTPReply.parsePASV("227 Entering Passive Mode") == nil)
        #expect(FTPReply.parsePASV("227 (1,2,3)") == nil)
        #expect(FTPReply.parsePASV("227 (1,2,3,4,5,999)") == nil)
    }
}
