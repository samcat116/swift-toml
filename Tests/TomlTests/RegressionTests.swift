/*
 * Regression coverage for the safety and performance defects fixed during the
 * Swift 6.3 migration. Each test names the behaviour that used to be wrong.
 */

import Testing
@testable import Toml
import Foundation

// MARK: - Crashes

@Suite("Malformed input is reported, not fatal")
struct CrashRegressionTests {

    @Test("Nested inline tables parse instead of trapping")
    func nestedInlineTables() throws {
        // `extractTableTokens` stopped at the first InlineTableEnd, leaving
        // the outer closing brace in the stream. The top-level parse loop
        // then hit a force-unwrapped dispatch-table lookup and trapped -- on
        // input that is perfectly valid TOML.
        let two = try Toml(withString: "a = {b = {c = 1}}")
        #expect(two.int("a", "b", "c") == 1)

        let three = try Toml(withString: "a = {b = {c = {d = 1}}}")
        #expect(three.int("a", "b", "c", "d") == 1)

        let mixed = try Toml(withString: "a = {b = 1, c = {d = 2, e = {f = 3}}}")
        #expect(mixed.int("a", "b") == 1)
        #expect(mixed.int("a", "c", "d") == 2)
        #expect(mixed.int("a", "c", "e", "f") == 3)
    }

    @Test("Deeply nested inline tables stay bounded")
    func deeplyNestedInlineTables() throws {
        let depth = 50
        let doc = "a = " + String(repeating: "{b = ", count: depth) + "1"
            + String(repeating: "}", count: depth)
        let toml = try Toml(withString: doc)
        #expect(toml.int(["a"] + Array(repeating: "b", count: depth)) == 1)
    }

    @Test("Truncated table declaration after a table array throws")
    func truncatedTableAfterTableArray() {
        // getTableTokens indexed subKeyPath[0] without checking that the
        // trailing declaration produced any name at all.
        #expect(throws: TomlError.self) {
            _ = try Toml(withString: "[[a.b]]\nc=1[")
        }
    }

    @Test("Truncated table array declaration throws")
    func truncatedTableArray() {
        // These used to be accepted silently and produce an empty document.
        #expect(throws: TomlError.self) { _ = try Toml(withString: "[[a.b") }
        #expect(throws: TomlError.self) { _ = try Toml(withString: "[[a.b]]\n[[a") }
    }

    @Test("Unbalanced closing tokens throw rather than trapping")
    func unbalancedClosers() {
        for doc in ["a = [1,2]]", "a = 1\n]", "a = {b = 1}}"] {
            #expect(throws: (any Error).self, "expected \(doc) to be rejected") {
                _ = try Toml(withString: doc)
            }
        }
    }
}

// MARK: - Silent data loss

@Suite("Escape sequences")
struct EscapeRegressionTests {

    @Test("Incomplete unicode escape is an error, not an empty string")
    func incompleteUnicodeEscape() {
        // `a = "\u00"` used to parse successfully and yield "": the
        // incomplete escape, and the rest of the string with it, was dropped.
        #expect(throws: TomlError.self) { _ = try Toml(withString: #"a = "\u00""#) }
        #expect(throws: TomlError.self) { _ = try Toml(withString: #"a = "\U0001F49""#) }
        #expect(throws: TomlError.self) { _ = try Toml(withString: #"a = "abc\u12""#) }
    }

    @Test("Complete unicode escapes still decode")
    func completeUnicodeEscapes() throws {
        #expect(try Toml(withString: #"a = "é""#).string("a") == "é")
        #expect(try Toml(withString: #"a = "\U0001F600""#).string("a") == "😀")
        #expect(try Toml(withString: #"a = "xAy""#).string("a") == "xAy")
    }

    @Test("Invalid unicode scalars are rejected")
    func invalidScalars() {
        // Surrogate halves are not scalar values.
        #expect(throws: TomlError.self) { _ = try Toml(withString: #"a = "\uD800""#) }
        #expect(throws: TomlError.self) { _ = try Toml(withString: #"a = "\U00110000""#) }
    }

    @Test("Escaped backslash before a newline is not a line continuation")
    func escapedBackslashIsNotContinuation() throws {
        // stripLineContinuation used to regex-match `\` + whitespace and then
        // call replacingOccurrences for each hit, which both mistook the
        // second half of an escaped `\\` for a continuation and stripped
        // every other copy of the matched text in the string.
        let toml = try Toml(withString: "a = \"\"\"x\\\\\ny\"\"\"")
        #expect(toml.string("a") == "x\\\ny")
    }

    @Test("Line continuations still fold whitespace")
    func lineContinuations() throws {
        let toml = try Toml(withString: "a = \"\"\"The quick \\\n    brown fox\"\"\"")
        #expect(toml.string("a") == "The quick brown fox")
    }
}

// MARK: - Hashing

@Suite("Key paths")
struct PathRegressionTests {

    @Test("Paths that are permutations of each other hash apart")
    func permutationsDoNotCollide() {
        // The hash was `components.reduce(0, ^)`, which is order-independent
        // and self-cancelling: every permutation collided, and any path with
        // a repeated component collided with the empty path.
        let ab = Path(["a", "b"])
        let ba = Path(["b", "a"])
        #expect(ab != ba)
        #expect(ab.hashValue != ba.hashValue)

        let aa = Path(["a", "a"])
        let empty = Path([])
        #expect(aa.hashValue != empty.hashValue)
    }

    @Test("Distinct permuted paths keep distinct values")
    func permutedPathsRoundTrip() throws {
        let toml = try Toml(withString: """
            [a.b.c]
            v = 1

            [c.b.a]
            v = 2
            """)
        #expect(toml.int("a", "b", "c", "v") == 1)
        #expect(toml.int("c", "b", "a", "v") == 2)
    }

    @Test("begins(with:) matches only true prefixes")
    func beginsWith() {
        let path = Path(["a", "b", "c"])
        #expect(path.begins(with: ["a"]))
        #expect(path.begins(with: ["a", "b"]))
        #expect(path.begins(with: ["a", "b", "c"]))
        #expect(!path.begins(with: ["b"]))
        #expect(!path.begins(with: ["a", "b", "c", "d"]))
    }
}

// MARK: - Table presence

@Suite("table(_:) presence semantics")
struct TableAccessorRegressionTests {

    @Test("An absent table is nil, not an empty table")
    func absentTableIsNil() throws {
        // `table(_:)` delegated straight to the non-optional `table(from:)`,
        // which builds a view out of whatever matches the prefix -- nothing,
        // for a section that is not in the document. The optional return
        // therefore never was nil and every caller's `if let` was dead code.
        let toml = try Toml(withString: "a = 1")
        #expect(toml.table("missing") == nil)
        #expect(toml.table("a", "b") == nil)
        #expect(toml.table("missing", "deeper") == nil)
    }

    @Test("A declared table is returned, including empty and implicit ones")
    func declaredTablesArePresent() throws {
        let toml = try Toml(withString: """
            [empty]

            [a.b]
            v = 1
            """)
        #expect(toml.table("empty") != nil)
        #expect(toml.table("a", "b")?.int("v") == 1)
        // `a` is only implied by `[a.b]`, but the parser registers it.
        #expect(toml.table("a")?.int("b", "v") == 1)
    }

    @Test("Inline tables and arrays of tables are present")
    func inlineTablesAndTableArrays() throws {
        let inline = try Toml(withString: "a = {b = 1}")
        #expect(inline.table("a")?.int("b") == 1)

        // `[[a.b]]` stores `a.b` as a key holding [Toml] rather than as a
        // table name, so `a` is reachable only as a prefix of that key.
        let arrayOfTables = try Toml(withString: "[[a.b]]\nid = 1")
        #expect(arrayOfTables.table("a", "b") != nil)
        #expect(arrayOfTables.table("a") != nil)
        let nested: [Toml]? = arrayOfTables.table("a")?.array("b")
        #expect(nested?.first?.int("id") == 1)
    }

    @Test("A key that is not a table is still reachable as a table view")
    func dottedKeysWithoutAnExplicitTable() throws {
        let toml = try Toml(withString: "a.b.c = 1")
        #expect(toml.table("a")?.int("b", "c") == 1)
        #expect(toml.table("a", "b")?.int("c") == 1)
        #expect(toml.table("a", "b", "c") != nil)   // the key itself
        #expect(toml.table("a", "b", "d") == nil)
    }

    @Test("The root table is never nil")
    func rootTableIsAlwaysPresent() throws {
        #expect(try Toml(withString: "").table() != nil)
        #expect(try Toml(withString: "a = 1").table() != nil)
    }

    @Test("table(from:) still builds a view unconditionally")
    func tableFromStaysUnconditional() throws {
        // The explicit "give me a view, empty or not" API is unchanged.
        let toml = try Toml(withString: "a = 1")
        let empty = toml.table(from: ["missing"])
        #expect(empty.keyNames.isEmpty)
        #expect(empty.tableNames.isEmpty)
    }
}

// MARK: - Tokens

@Suite("Token identity")
struct TokenRegressionTests {

    @Test("Tokens compare by case, not by hash value")
    func tokensCompareByCase() {
        // Equality was `lhs.hashValue == rhs.hashValue`, which made
        // correctness depend on hashing rather than on the case itself.
        #expect(Token.Identifier("a") == Token.Identifier("b"))
        #expect(Token.IntegerNumber(1) == Token.IntegerNumber(2))
        #expect(Token.Identifier("a") != Token.Key(["a"]))
        #expect(Token.TableBegin != Token.TableEnd)
    }
}

// MARK: - Dates

@Suite("Date handling")
struct DateRegressionTests {

    @Test("Offset date-times parse in every accepted spelling")
    func offsetDateTimes() throws {
        let utc = try Toml(withString: "d = 1979-05-27T07:32:00Z").date("d")
        // The grammar accepts a lowercase 'z' too.
        let lower = try Toml(withString: "d = 1979-05-27T07:32:00z").date("d")
        #expect(utc == lower)

        let offset = try Toml(withString: "d = 1979-05-27T00:32:00-07:00").date("d")
        #expect(offset == utc)
    }

    @Test("Fractional seconds of varying length parse")
    func fractionalSeconds() throws {
        for text in ["1979-05-27T07:32:00.9Z",
                     "1979-05-27T07:32:00.123Z",
                     "1979-05-27T07:32:00.999999Z"] {
            #expect(try Toml(withString: "d = \(text)").date("d") != nil,
                    "failed to parse \(text)")
        }
    }

    @Test("Local date, time and date-time keep their text form")
    func localTypes() throws {
        let toml = try Toml(withString: """
            d = 1979-05-27
            t = 07:32:00
            dt = 1979-05-27T07:32:00
            """)
        #expect(toml.localDate("d") == "1979-05-27")
        #expect(toml.localTime("t") == "07:32:00")
        #expect(toml.localDateTime("dt") == "1979-05-27T07:32:00")
    }
}

// MARK: - Performance

@Suite("Scaling")
struct PerformanceRegressionTests {

    @Test("Parse time grows linearly with document size")
    func parseScalesLinearly() throws {
        // The lexer used to rebuild a String of the remaining document for
        // every token, making tokenization quadratic: a 93 KB document took
        // almost four seconds. Compare the per-byte cost at two sizes rather
        // than asserting a wall-clock budget, so the test does not depend on
        // how fast the host is.
        func document(keys: Int) -> String {
            var doc = ""
            doc.reserveCapacity(keys * 28)
            for i in 0..<keys { doc += "key\(i) = \"value number \(i)\"\n" }
            return doc
        }

        func elapsed(parsing doc: String) throws -> Double {
            let start = ContinuousClock.now
            _ = try Toml(withString: doc)
            return Double((ContinuousClock.now - start).components.attoseconds) / 1e18
        }

        let small = document(keys: 500)
        let large = document(keys: 4000)   // 8x the work

        _ = try elapsed(parsing: small)    // warm up
        let smallTime = try elapsed(parsing: small)
        let largeTime = try elapsed(parsing: large)

        // Linear would be ~8x. Quadratic would be ~64x. A generous ceiling of
        // 24x fails loudly on a return to quadratic behaviour without being
        // flaky on a loaded machine.
        let ratio = largeTime / max(smallTime, 1e-9)
        #expect(ratio < 24,
                Comment(rawValue: "8x the input took \(String(format: "%.1f", ratio))x "
                        + "the time; expected roughly linear scaling"))
    }
}

// MARK: - Concurrency

@Suite("Concurrent use")
struct ConcurrencyRegressionTests {

    @Test("The shared grammar is safe to parse with from many tasks")
    func concurrentParsing() async throws {
        // Grammar.shared is built once and read from every parse; this
        // exercises that sharing, including the lazily lowered regex programs.
        let doc = """
            title = "concurrent"

            [owner]
            name = "someone"

            [[items]]
            id = 1

            [[items]]
            id = 2
            """

        let results = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<64 {
                group.addTask {
                    try? Toml(withString: doc).string("owner", "name")
                }
            }
            var seen: [String?] = []
            for await result in group { seen.append(result) }
            return seen
        }

        #expect(results.count == 64)
        #expect(results.allSatisfy { $0 == "someone" })
    }
}
