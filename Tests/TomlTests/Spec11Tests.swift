/*
 * Tests for the syntax TOML 1.1.0 added, and for the 1.0.0 constructs that
 * were found missing while implementing it.
 *
 * The exhaustive check is `Scripts/toml-test.sh`, which runs the whole
 * toml-test suite; these cover the same ground in a form that fails with a
 * useful message and runs as part of `swift test`.
 */

import Testing
import Foundation
@testable import Toml

// MARK: - TOML 1.1.0

@Suite("TOML 1.1.0 syntax")
struct Spec11Tests {

    @Test("Inline tables may span several lines")
    func multiLineInlineTable() throws {
        let toml = try Toml(withString: """
            point = {
              # the x coordinate
              x = 1,
              y = 2,
            }
            """)
        #expect(toml.int("point", "x") == 1)
        #expect(toml.int("point", "y") == 2)
    }

    @Test("Inline tables may end with a comma")
    func inlineTableTrailingComma() throws {
        let toml = try Toml(withString: "t = { a = 1, b = 2, }")
        #expect(toml.int("t", "b") == 2)
    }

    @Test("A comma still has to separate entries")
    func inlineTableSeparators() throws {
        for text in ["t = {,}", "t = { a = 1,, b = 2 }", "t = { a = 1 b = 2 }"] {
            #expect(throws: (any Error).self, "accepted \(text)") {
                try Toml(withString: text)
            }
        }
    }

    @Test("\\xHH escapes a code point up to U+00FF")
    func hexEscapes() throws {
        let toml = try Toml(withString: #"s = "\x41\x7f\xff""#)
        #expect(toml.string("s") == "A\u{7F}\u{FF}")
    }

    @Test("\\xHH needs two hex digits")
    func invalidHexEscape() throws {
        #expect(throws: (any Error).self) {
            try Toml(withString: #"s = "\xAg""#)
        }
    }

    @Test("\\e is the escape character")
    func escapeEscape() throws {
        let toml = try Toml(withString: #"s = "\e[0m""#)
        #expect(toml.string("s") == "\u{1B}[0m")
    }

    @Test("Seconds are optional")
    func optionalSeconds() throws {
        let toml = try Toml(withString: """
            offset = 1979-05-27T07:32Z
            local = 1979-05-27T07:32
            time = 07:32
            """)
        #expect(toml.date("offset") == Date(rfc3339String: "1979-05-27T07:32:00Z")!)
        #expect(toml.localDateTime("local") == "1979-05-27T07:32")
        #expect(toml.localTime("time") == "07:32")
    }
}

// MARK: - TOML 1.0.0 constructs that were missing

@Suite("Specification conformance")
struct SpecConformanceTests {

    @Test("A space or lowercase t may separate the date from the time")
    func dateTimeSeparators() throws {
        let expected = Date(rfc3339String: "1979-05-27T07:32:00Z")!
        for text in ["1979-05-27 07:32:00Z", "1979-05-27t07:32:00z", "1979-05-27T07:32:00Z"] {
            #expect(try Toml(withString: "d = \(text)").date("d") == expected,
                    "failed to parse \(text)")
        }
    }

    @Test("Dotted keys may have quoted parts")
    func quotedDottedKeys() throws {
        let toml = try Toml(withString: """
            a."b.c".'d e' = 1
            "f.g" = 2
            """)
        #expect(toml.int("a", "b.c", "d e") == 1)
        // The dots inside a quoted key are part of the name, not separators.
        #expect(toml.int("f.g") == 2)
    }

    @Test("Table names may be spaced out, and quoted")
    func tableNameWhitespace() throws {
        let toml = try Toml(withString: """
            [ a . "b c" ]
            d = 1
            """)
        #expect(toml.int("a", "b c", "d") == 1)
    }

    @Test("Two names in a table header must be separated by a dot")
    func tableNameMissingSeparator() throws {
        #expect(throws: (any Error).self) {
            try Toml(withString: "[a b]")
        }
    }

    @Test("Multi-line strings keep their leading and trailing whitespace")
    func multiLineStringWhitespace() throws {
        let toml = try Toml(withString: "s = \"\"\"\n  padded  \n\"\"\"")
        // Only the newline after the opening delimiter is dropped.
        #expect(toml.string("s") == "  padded  \n")
    }

    @Test("Multi-line strings may contain and end with their delimiter")
    func multiLineStringQuotes() throws {
        let toml = try Toml(withString: #"""
            a = """Here are two quotation marks: "". Simple enough."""
            b = """"This," she said, "is just a pointless statement.""""
            c = '''Here are fifteen quotation marks: """""""""""""""'''
            """#)
        #expect(toml.string("a") == #"Here are two quotation marks: "". Simple enough."#)
        #expect(toml.string("b") == #""This," she said, "is just a pointless statement.""#)
        #expect(toml.string("c") == #"Here are fifteen quotation marks: """"""""""""""""#)
    }

    @Test("CRLF line endings work inside multi-line strings")
    func multiLineStringCRLF() throws {
        let toml = try Toml(withString: "s = '''\r\nfirst\r\nsecond'''")
        #expect(toml.string("s") == "first\nsecond")
    }

    @Test("A backslash continues a line only at the end of one")
    func lineContinuation() throws {
        let joined = try Toml(withString: "s = \"\"\"a \\\n    b\"\"\"")
        #expect(joined.string("s") == "a b")

        #expect(throws: (any Error).self) {
            try Toml(withString: "s = \"\"\"a \\  b\"\"\"")
        }
    }

    @Test("Strings may hold characters outside the basic multilingual plane")
    func astralCharacters() throws {
        let toml = try Toml(withString: #""𐀀" = "🎉""#)
        #expect(toml.string("𐀀") == "🎉")
    }

    @Test("Control characters are not string, key or comment content")
    func controlCharacters() throws {
        for text in ["s = \"a\u{0}b\"", "s = 'a\u{7F}b'", "# comment\u{0}", "a = 1\rb = 2"] {
            #expect(throws: (any Error).self, "accepted \(text.debugDescription)") {
                try Toml(withString: text)
            }
        }
    }

    @Test("Numbers may not have leading zeros or stray underscores")
    func numberFormats() throws {
        for text in ["a = 01", "a = +01", "a = 1__0", "a = 1_", "a = 0x_1",
                     "a = 0b12", "a = 1.", "a = .1", "a = 1_.0", "a = 1e_1"] {
            #expect(throws: (any Error).self, "accepted \(text)") {
                try Toml(withString: text)
            }
        }

        // Underscores between digits are fine, and an exponent may have a
        // leading zero even though the integer part may not.
        let toml = try Toml(withString: "a = 1_000\nb = 0x1_2\nc = 1e01")
        #expect(toml.int("a") == 1000)
        #expect(toml.int("b") == 0x12)
        #expect(toml.double("c") == 10.0)
    }

    @Test("Date and time components have to be in range")
    func dateTimeRanges() throws {
        for text in ["d = 2023-02-29", "d = 2023-13-01", "d = 2023-01-32",
                     "t = 25:00:00", "t = 00:60:00", "d = 2023-01-01T00:00:61"] {
            #expect(throws: (any Error).self, "accepted \(text)") {
                try Toml(withString: text)
            }
        }
        // 2024 is a leap year, and 60 seconds is a leap second.
        #expect(try Toml(withString: "d = 2024-02-29").localDate("d") == "2024-02-29")
        #expect(try Toml(withString: "t = 23:59:60").localTime("t") == "23:59:60")
    }

    @Test("Unclosed constructs are errors, not partial documents")
    func unterminatedConstructs() throws {
        for text in ["a = [1, 2", "a = { b = 1", "a = \"unterminated", "a = '''unterminated"] {
            #expect(throws: (any Error).self, "accepted \(text)") {
                try Toml(withString: text)
            }
        }
    }

    @Test("A key/value pair or table header ends its line")
    func endOfLine() throws {
        for text in ["a = 1 b = 2", "first = \"Tom\" last = \"P\"", "[[a]] b = 1", "[a] b = 1"] {
            #expect(throws: (any Error).self, "accepted \(text)") {
                try Toml(withString: text)
            }
        }
        // A comment may still follow.
        #expect(try Toml(withString: "a = 1 # trailing").int("a") == 1)
    }

    @Test("Array elements are separated by exactly one comma")
    func arraySeparators() throws {
        for text in ["a = [,]", "a = [1,,2]", "a = [1 2]"] {
            #expect(throws: (any Error).self, "accepted \(text)") {
                try Toml(withString: text)
            }
        }
        let toml = try Toml(withString: "a = [1, 2, ]")
        #expect(toml.array("a") as [Int]? == [1, 2])
    }

    @Test("A defined key cannot be redefined or extended")
    func redefinition() throws {
        for text in [
            "a = 1\na.b = 2",             // a is not a table
            "a = 1\n[a.b]",               // nor can one be opened underneath it
            "a = {}\n[a.b]",              // an inline table is closed
            "a.b = 0\na = {}",            // and cannot replace a table
            "[a.b.c]\nz = 9\n[a]\nb.c.t = 1",  // nor may a dotted key reopen one
            "fruit = []\n[[fruit]]",      // an array is not an array of tables
            "[[a.b]]\n[[a]]",             // and `a` here is a table, not one either
        ] {
            #expect(throws: (any Error).self, "accepted \(text.debugDescription)") {
                try Toml(withString: text)
            }
        }
    }

    @Test("An array of tables can still be extended and nested")
    func tableArrays() throws {
        let toml = try Toml(withString: """
            [[fruit]]
            name = "apple"

            [fruit.physical]
            colour = "red"

            [[fruit]]
            name = "banana"
            """)
        let fruit: [Toml] = toml.array("fruit")!
        #expect(fruit.count == 2)
        #expect(fruit[0].string("name") == "apple")
        #expect(fruit[0].string("physical", "colour") == "red")
        #expect(fruit[1].string("name") == "banana")
    }

    @Test("Local dates and times round-trip as dates, not strings")
    func localValuesRoundTrip() throws {
        let toml = try Toml(withString: "d = 1979-05-27\nt = 07:32:00")
        #expect(toml.tomlDate("d")?.kind == .localDate)
        // Serialized bare: quoting one would turn it into a string.
        #expect(toml.description.contains("d = 1979-05-27"))
        #expect(toml.description.contains("t = 07:32:00"))
        #expect(try Toml(withString: toml.description).localDate("d") == "1979-05-27")
    }
}
