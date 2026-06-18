import Testing
import FP
@testable import Slvnt

@Suite("TransferCode")
struct TransferCodeTests {
    @Test("accepts four digits, trimming whitespace")
    func valid() throws {
        #expect(try TransferCode.validate("1234").get() == "1234")
        #expect(try TransferCode.validate("  0000 ").get() == "0000")
    }

    @Test("rejects anything that is not exactly four digits")
    func invalid() {
        for bad in ["123", "12345", "12a4", "", "abcd"] {
            #expect(throws: SlvntError.self) { try TransferCode.validate(bad).get() }
        }
    }
}
