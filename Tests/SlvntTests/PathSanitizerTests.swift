import Testing
@testable import Slvnt

@Suite("PathSanitizer")
struct PathSanitizerTests {
    @Test("replaces illegal characters with underscore")
    func illegal() {
        #expect(PathSanitizer.sanitize("AC/DC") == "AC_DC")
        #expect(PathSanitizer.sanitize("a:b*c?d") == "a_b_c_d")
    }

    @Test("collapses runs of underscores")
    func collapse() {
        #expect(PathSanitizer.sanitize("a///b") == "a_b")
    }

    @Test("trims surrounding whitespace and dots")
    func trim() {
        #expect(PathSanitizer.sanitize("  hello.  ") == "hello")
        #expect(PathSanitizer.sanitize("...name...") == "name")
    }

    @Test("empty or all-illegal result becomes Unknown")
    func emptyBecomesUnknown() {
        #expect(PathSanitizer.sanitize("") == "Unknown")
        #expect(PathSanitizer.sanitize("...") == "Unknown")
    }

    @Test("leaves clean names untouched")
    func clean() {
        #expect(
            PathSanitizer.sanitize("Selected Ambient Works 85-92") == "Selected Ambient Works 85-92"
        )
    }
}
