/*
 * Copyright 2016-2018 JD Fergason
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation

struct Grammar: Sendable {
    // The grammar is immutable, and compiling ~45 regular expressions is by
    // far the most expensive part of building it. Sharing one instance keeps
    // that off the per-parse path; it used to be rebuilt for every document.
    static let shared = Grammar()

    let grammar: [String: [Evaluator]]

    init() {
        grammar = [
            "comment": Self.commentEvaluators(),
            "string": Self.stringEvaluators(),
            "literalString": Self.literalStringEvaluators(),
            "multilineString": Self.multiLineStringEvaluators(),
            "multilineLiteralString": Self.multiLineStringLiteralEvaluators(),
            "tableName": Self.tableNameEvaluators(),
            "tableArray": Self.tableArrayEvaluators(),
            "value": Self.valueEvaluators(endOfLine: true),
            "inlineValue": Self.valueEvaluators(),
            "eol": Self.endOfLineEvaluators(),
            "array": Self.arrayEvaluators(),
            "inlineTable": Self.inlineTableEvaluators(),
            "root": Self.rootEvaluators(),
        ]
    }

    private static func commentEvaluators() -> [Evaluator] {
        // A comment runs to the end of the line and may hold anything except
        // a control character -- `.*` matched those too, so a NUL or a stray
        // carriage return inside a comment went unnoticed.
        return [
            // to enable saving comments in the tokenizer use the following line
            // Evaluator(regex: commentChars, generator: { (r: Substring) in .Comment(r.trim()) }, pop: true)
            Evaluator(regex: "[\t\\u0020-\\u007E\\u0080-\\x{10FFFF}]*",
                generator: { _ in nil }, pop: true)
        ]
    }

    private static func stringEvaluators() -> [Evaluator] {
        return [
            Evaluator(regex: "\"", generator: { _ in nil }, pop: true),
            // An escaped backslash is matched before an escaped quote, so that
            // the closing quote of `"ends here\\"` is seen as the end of the
            // string rather than as the `\"` of an escape -- which ran the
            // string on into the rest of the document.
            Evaluator(regex: "([\t\\u0020-\\u0021\\u0023-\\u005B\\u005D-\\u007E\\u0080-\\x{10FFFF}]|\\\\\\\\|\\\\\"|\\\\)+",
                generator: { (r: Substring) throws(TomlError) in
                    .Identifier(try String(r).replaceEscapeSequences())
                })
        ]
    }

    private static func literalStringEvaluators() -> [Evaluator] {
        return [
            Evaluator(regex: "'", generator: { _ in nil }, pop: true),
            Evaluator(regex: "([\t\\u0020-\\u0026\\u0028-\\u007E\\u0080-\\x{10FFFF}])+",
                generator: { (r: Substring) in .Identifier(String(r)) })
        ]
    }

    /**
        The body of a multi-line string, matched together with the delimiter
        that closes it.

        The closing delimiter is a run of three to five delimiter characters,
        of which the last three end the string and any others are the last
        characters of its content -- which is what allows a multi-line string
        to end with a quote, as in `"""...ends with a quote""""`. Content may
        also contain runs of one or two delimiter characters anywhere.

        Matching the close as part of the same pattern is what makes that
        possible: the previous grammar had the body and the closing delimiter
        as separate evaluators, so the body had to stop at the first run of
        three, and a string could neither contain nor end with one.

        - Parameter delimiter: `"` or `'`
        - Parameter bodyChars: Character class for content, excluding the
                               delimiter and (for basic strings) the backslash
        - Parameter escapes: Whether a backslash escapes the next character
    */
    private static func multiLineStringPattern(delimiter: String, bodyChars: String,
                                               escapes: Bool) -> String {
        let alternatives = (escapes ? ["\\\\."] : []) +
            // A carriage return is content only as part of a CRLF line
            // ending; on its own it is a stray control character.
            ["\r\n", bodyChars, delimiter + "(?!" + delimiter + delimiter + ")"]
        return "(" + alternatives.joined(separator: "|") + ")*" + delimiter + "{3,5}"
    }

    private static func multiLineStringEvaluators() -> [Evaluator] {
        // A tab is as legal inside a multi-line string as a space is, and
        // CRLF is handled by the pattern builder; the previous class admitted
        // neither, so a document with CRLF line endings could not contain a
        // multi-line string at all.
        let bodyChars = "[\n\t\\u0020-\\u0021\\u0023-\\u005B\\u005D-\\u007E\\u0080-\\x{10FFFF}]"
        return [
            Evaluator(regex: multiLineStringPattern(delimiter: "\"", bodyChars: bodyChars,
                                                    escapes: true),
                // Line continuations are resolved before escape sequences: a
                // continuation is a backslash followed by whitespace, and
                // resolving escapes first destroys the backslash that
                // identifies it.
                generator: { (r: Substring) throws(TomlError) in
                    .Identifier(try multiLineStringBody(r).multilineStringContent()
                        .stripLineContinuation().replaceEscapeSequences())
                }, pop: true, multiline: true)
        ]
    }

    private static func multiLineStringLiteralEvaluators() -> [Evaluator] {
        let bodyChars = "[\n\t\\u0020-\\u0026\\u0028-\\u007E\\u0080-\\x{10FFFF}]"
        return [
            Evaluator(regex: multiLineStringPattern(delimiter: "'", bodyChars: bodyChars,
                                                    escapes: false),
                generator: { (r: Substring) in
                    .Identifier(multiLineStringBody(r).multilineStringContent())
                }, pop: true, multiline: true)
        ]
    }

    private static func tableNameEvaluators() -> [Evaluator] {
        let tableErrorStr = "Invalid table name declaration"
        return [
            // Whitespace may surround the parts of a table name:
            // `[ g . h . i ]` names the same table as `[g.h.i]`.
            Evaluator(regex: "[ \t]+", generator: { _ in nil }),
            // An empty quoted name is a legal, if inadvisable, table name, so
            // the empty pair is matched here rather than left to the string
            // states, which require at least one character.
            Evaluator(regex: "\"\"", generator: { _ in .Identifier("") }),
            Evaluator(regex: "''", generator: { _ in .Identifier("") }),
            Evaluator(regex: "\"", generator: { _ in nil }, push: ["string"]),
            Evaluator(regex: "'", generator: { _ in nil }, push: ["literalString"]),
            Evaluator(regex: "\\.", generator: { _ in .TableSep }),
            // opening [ are prohibited directly within a table declaration
            Evaluator(regex: "\\[", generator: { _ throws(TomlError) in throw TomlError.syntaxError(tableErrorStr) }),
            // hashes are prohibited directly within a table declaration
            Evaluator(regex: "#", generator: { _ throws(TomlError) in throw TomlError.syntaxError(tableErrorStr) }),
            Evaluator(regex: "[A-Za-z0-9_-]+", generator: { (r: Substring) in .Identifier(String(r)) }),
            Evaluator(regex: "\\]\\]", generator: { _ in .TableArrayEnd }, pop: true),
            Evaluator(regex: "\\]", generator: { _ in .TableEnd }, pop: true),
        ]
    }

    private static func tableArrayEvaluators() -> [Evaluator] {
        let tableErrorStr = "Invalid table name declaration"
        return [
            // Whitespace may surround the parts of a table name:
            // `[ g . h . i ]` names the same table as `[g.h.i]`.
            Evaluator(regex: "[ \t]+", generator: { _ in nil }),
            // An empty quoted name is a legal, if inadvisable, table name, so
            // the empty pair is matched here rather than left to the string
            // states, which require at least one character.
            Evaluator(regex: "\"\"", generator: { _ in .Identifier("") }),
            Evaluator(regex: "''", generator: { _ in .Identifier("") }),
            Evaluator(regex: "\"", generator: { _ in nil }, push: ["string"]),
            Evaluator(regex: "'", generator: { _ in nil }, push: ["literalString"]),
            Evaluator(regex: "\\.", generator: { _ in .TableSep }),
            // opening [ are prohibited directly within a table declaration
            Evaluator(regex: "\\[", generator: { _ throws(TomlError) in throw TomlError.syntaxError(tableErrorStr) }),
            // hashes are prohibited directly within a table declaration
            Evaluator(regex: "#", generator: { _ throws(TomlError) in throw TomlError.syntaxError(tableErrorStr) }),
            Evaluator(regex: "[A-Za-z0-9_-]+", generator: { (r: Substring) in .Identifier(String(r)) }),
            Evaluator(regex: "\\]\\]", generator: { _ in .TableArrayEnd }, pop: true),
        ]
    }

    private static func dateValueEvaluators() -> [Evaluator] {
        let dateStr = "\\d{4}-\\d{2}-\\d{2}"
        // Seconds are optional as of TOML 1.1.0; fractional seconds still
        // require them, and may have any number of digits.
        let timeStr = "\\d{2}:\\d{2}(:\\d{2}(\\.\\d+)?)?"
        // RFC 3339 permits a lower case `t`, and TOML additionally permits a
        // space, in place of the `T` that separates the date from the time.
        let sepStr = "[Tt ]"
        let offsetStr = "([Zz]|[-\\+]\\d{2}:\\d{2})"

        return [
            // Offset date-time
            Evaluator(regex: dateStr + sepStr + timeStr + offsetStr, generator: {
                (r: Substring) throws(TomlError) in
                    guard let date = Date(rfc3339String: try validatedDateTime(r)) else {
                        throw TomlError.invalidDateFormat(String(r))
                    }
                    return Token.DateTime(date)
            }, pop: true),
            // Local date-time: no offset
            Evaluator(regex: dateStr + sepStr + timeStr, generator: {
                (r: Substring) throws(TomlError) in
                    return Token.LocalDateTime(normalizedDateTimeSeparator(try validatedDateTime(r)[...]))
            }, pop: true),
            // Local date: date only
            Evaluator(regex: dateStr, generator: { (r: Substring) throws(TomlError) in
                return Token.LocalDate(try validatedDateTime(r))
            }, pop: true),
            // Local time: time only
            Evaluator(regex: timeStr, generator: { (r: Substring) throws(TomlError) in
                return Token.LocalTime(try validatedDateTime(r))
            }, pop: true),
        ]
    }

    private static func stringValueEvaluators() -> [Evaluator] {
        return [
            // Multi-line string values (must come before single-line test).
            // The empty cases need no special handling: the body pattern
            // matches nothing and the delimiter closes it.
            Evaluator(regex: "\"\"\"", generator: { _ in nil },
                push: ["multilineString"], pop: true),
            // Multi-line literal string values (must come before single-line test)
            Evaluator(regex: "'''", generator: { _ in nil },
                push: ["multilineLiteralString"], pop: true),
            // empty single line strings
            Evaluator(regex: "\"\"", generator: { _ in .Identifier("") }, pop: true),
            Evaluator(regex: "''", generator: { _ in .Identifier("") }, pop: true),
            // String values
            Evaluator(regex: "\"", generator: { _ in nil }, push: ["string"], pop: true),
            // Literal string values
            Evaluator(regex: "'", generator: { _ in nil }, push: ["literalString"], pop: true),
        ]
    }

    private static func doubleValueEvaluators() -> [Evaluator] {
        let generator: TokenGenerator = { (val: Substring) throws(TomlError) in
            let cleaned = val.replacingOccurrences(of: "_", with: "")
            if let value = Double(cleaned) {
                return .DoubleNumber(value)
            } else {
                throw TomlError.invalidNumberFormat("Invalid float: \(val)")
            }
        }
        return [
            // Double values with exponent (with optional underscores)
            Evaluator(regex: decimalIntPattern + "(" + fractionPattern + ")?" + exponentPattern,
                generator: generator, pop:true),
            // Double values no exponent (with optional underscores)
            Evaluator(regex: decimalIntPattern + fractionPattern, generator: generator, pop: true),
        ]
    }

    // An underscore in a number must separate two digits: `1_000` is a
    // thousand, while `1__0`, `1_` and `_1` are errors. A leading zero is an
    // error too, except for the number zero itself. These patterns used to be
    // `[0-9][0-9_]*` and friends, which accepted all of those.
    private static let decimalIntPattern = "[-\\+]?(0|[1-9](_?[0-9])*)"
    private static let fractionPattern = "\\.[0-9](_?[0-9])*"
    // Unlike the integer part, an exponent may have leading zeros.
    private static let exponentPattern = "[eE][-\\+]?[0-9](_?[0-9])*"

    private static func intValueEvaluators() -> [Evaluator] {
        /// Build a generator for an integer literal in `radix` with a
        /// two-character prefix such as `0x`.
        func radixGenerator(prefix: Int, radix: Int, name: String) -> TokenGenerator {
            { (r: Substring) throws(TomlError) in
                let digits = r.dropFirst(prefix).replacingOccurrences(of: "_", with: "")
                guard let value = Int(digits, radix: radix) else {
                    throw TomlError.invalidNumberFormat("Invalid \(name): \(r)")
                }
                return .IntegerNumber(value)
            }
        }

        /// `0x` and friends, with underscores only between digits.
        func radixPattern(prefix: String, digits: String) -> String {
            prefix + digits + "(_?" + digits + ")*"
        }

        return [
            // Hexadecimal integer values (with optional underscores)
            Evaluator(regex: radixPattern(prefix: "0x", digits: "[0-9A-Fa-f]"),
                generator: radixGenerator(prefix: 2, radix: 16, name: "hexadecimal"), pop: true),
            // Octal integer values (with optional underscores)
            Evaluator(regex: radixPattern(prefix: "0o", digits: "[0-7]"),
                generator: radixGenerator(prefix: 2, radix: 8, name: "octal"), pop: true),
            // Binary integer values (with optional underscores)
            Evaluator(regex: radixPattern(prefix: "0b", digits: "[01]"),
                generator: radixGenerator(prefix: 2, radix: 2, name: "binary"), pop: true),
            // Decimal integer values (with optional underscores)
            Evaluator(regex: decimalIntPattern,
                generator: { (r: Substring) throws(TomlError) in
                    let cleaned = r.replacingOccurrences(of: "_", with: "")
                    guard let value = Int(cleaned) else {
                        throw TomlError.invalidNumberFormat("Invalid integer: \(r)")
                    }
                    return .IntegerNumber(value)
                }, pop: true),
        ]
    }

    private static func booleanValueEvaluators() -> [Evaluator] {
        return [
            // Boolean values
            Evaluator(regex: "true", generator: { _ in .Boolean(true) }, pop: true),
            Evaluator(regex: "false", generator: { _ in .Boolean(false) }, pop: true),
        ]
    }

    private static func specialFloatValueEvaluators() -> [Evaluator] {
        return [
            // Positive infinity
            Evaluator(regex: "\\+?inf", generator: { _ in .DoubleNumber(Double.infinity) }, pop: true),
            // Negative infinity
            Evaluator(regex: "-inf", generator: { _ in .DoubleNumber(-Double.infinity) }, pop: true),
            // Not a number (with optional sign)
            Evaluator(regex: "[+-]?nan", generator: { _ in .DoubleNumber(Double.nan) }, pop: true),
        ]
    }

    private static func whitespaceValueEvaluators() -> [Evaluator] {
        return [
            // Ignore white-space
            Evaluator(regex: "[ \t]", generator: { _ in nil }),
        ]
    }

    private static func arrayValueEvaluators() -> [Evaluator] {
        return [
            // Arrays
            Evaluator(regex: "\\[", generator: {
                _ in .ArrayBegin
            }, push: ["array"], pop: true),
        ]
    }

    private static func inlineTableValueEvaluators() -> [Evaluator] {
        return [
            // Inline tables
            Evaluator(regex: "\\{", generator: {
                _ in .InlineTableBegin
            }, push: ["inlineTable"], pop: true),
        ]
    }

    /**
        The evaluators for a single value.

        - Parameter endOfLine: Whether the value ends a line, in which case
                               the `eol` state is left behind it to insist
                               that nothing but whitespace and a comment
                               follows. A value inside an array or an inline
                               table is followed by its neighbours instead.
    */
    private static func valueEvaluators(endOfLine: Bool = false) -> [Evaluator] {
        let typeEvaluators = stringValueEvaluators() + dateValueEvaluators() +
            specialFloatValueEvaluators() + doubleValueEvaluators() + intValueEvaluators() + booleanValueEvaluators()

        let evaluators = whitespaceValueEvaluators() + arrayValueEvaluators() +
            inlineTableValueEvaluators() + typeEvaluators

        guard endOfLine else {
            return evaluators
        }
        // The whitespace evaluator matches nothing and must not push.
        return whitespaceValueEvaluators() + (arrayValueEvaluators() +
            inlineTableValueEvaluators() + typeEvaluators).map {
                Evaluator($0, pushingUnder: "eol")
            }
    }

    /**
        What may follow a value or a table header on the same line: nothing,
        beyond whitespace and a comment.

        Without this state `a = 1 b = 2` parsed as two key/value pairs.
    */
    private static func endOfLineEvaluators() -> [Evaluator] {
        return [
            Evaluator(regex: "[ \t]+", generator: { _ in nil }),
            Evaluator(regex: "#", generator: { _ in nil }, push: ["comment"]),
            Evaluator(regex: "(\r\n|\n)", generator: { _ in nil }, pop: true),
        ]
    }

    private static func arrayEvaluators() -> [Evaluator] {
        return [
            // Ignore white-space
            Evaluator(regex: "([ \t\n]|\r\n)", generator: { _ in nil }),

            // Comments
            Evaluator(regex: "#", generator: { _ in nil }, push: ["comment"]),

            // Arrays
            Evaluator(regex: "\\[", generator: { _ in .ArrayBegin }, push: ["array"]),
            Evaluator(regex: "\\]", generator: { _ in .ArrayEnd }, pop: true),
            // A separator, not a state change: an array holds a sequence of
            // values in one state, which is what lets it end on a trailing
            // comma. The comma used to push a state that only a value could
            // pop, so `[1, 2, ]` left the lexer inside a phantom array and
            // the rest of the document failed to parse. It is a token because
            // the parser has to see where the separators are to reject
            // `[1,,2]` and `[1 2]`.
            Evaluator(regex: ",", generator: { _ in .Comma }),
            // Values do not close the array they appear in.
        ] + valueEvaluators().map { Evaluator($0, pop: false) }
    }

    private static func stringKeyEvaluator(valueState: String = "value") -> [Evaluator] {
        // A key is a dot-separated sequence of segments, each of which may be
        // bare, basic-string quoted, or literal-string quoted, in any
        // combination: `a."b.c".'d' = 1` is one key of three components.
        // These used to be four separate patterns, which between them could
        // not express a quoted segment inside a dotted key at all.
        let basicKeyPattern = "\"([\t\\u0020-\\u0021\\u0023-\\u005B\\u005D-\\u007E\\u0080-\\x{10FFFF}]|\\\\\\\\|\\\\\"|\\\\)*\""
        let literalKeyPattern = "'[\t\\u0020-\\u0026\\u0028-\\u007E\\u0080-\\x{10FFFF}]*'"
        let bareKeyPattern = "[a-zA-Z0-9_-]+"
        let segmentPattern = "(" + basicKeyPattern + "|" + literalKeyPattern + "|" + bareKeyPattern + ")"

        return [
            Evaluator(regex: segmentPattern + "([ \t]*\\.[ \t]*" + segmentPattern + ")*[ \t]*=",
                generator: { (r: Substring) throws(TomlError) in .Key(try splitDottedKey(r)) },
                push: [valueState]),
        ]
    }

    private static func inlineTableEvaluators() -> [Evaluator] {
        return [
            // Ignore white-space. Newlines are TOML 1.1.0: an inline table
            // may be spread over several lines, and may carry a trailing
            // comma before its closing brace.
            Evaluator(regex: "([ \t\n]|\r\n)", generator: { _ in nil }),
            Evaluator(regex: ",", generator: { _ in .Comma }),
            // Comments, which 1.1.0 admits wherever a newline is allowed
            Evaluator(regex: "#", generator: { _ in nil }, push: ["comment"]),
            // inline-table
            Evaluator(regex: "\\{", generator: { _ in .InlineTableBegin }, push: ["inlineTable"]),
            Evaluator(regex: "\\}", generator: { _ in .InlineTableEnd }, pop: true),
            // A value inside an inline table is followed by its neighbours,
            // not by the end of a line.
        ] + stringKeyEvaluator(valueState: "inlineValue")
    }

    private static func rootEvaluators() -> [Evaluator] {
        return [
            // Ignore white-space. A carriage return counts only as part of a
            // CRLF line ending: on its own it is a control character, and
            // treating it as whitespace let one hide anywhere in a document.
            Evaluator(regex: "([ \t\n]|\r\n)", generator: { _ in nil }),
            // Comments
            Evaluator(regex: "#", generator: { _ in nil }, push: ["comment"]),
        ] + stringKeyEvaluator() + [
            // Array of tables (must come before table). The `eol` state under
            // the header state is what makes `[[a]] b = 1` an error.
            Evaluator(regex: "\\[\\[", generator: { _ in .TableArrayBegin }, push: ["eol", "tableArray"]),
            // Tables
            Evaluator(regex: "\\[", generator: { _ in .TableBegin }, push: ["eol", "tableName"]),
        ]
    }
}
