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
            "value": Self.valueEvaluators(),
            "array": Self.arrayEvaluators(),
            "inlineTable": Self.inlineTableEvaluators(),
            "root": Self.rootEvaluators(),
        ]
    }

    private static func commentEvaluators() -> [Evaluator] {
        return [
            Evaluator(regex: "[\r\n]", generator: { _ in nil }, pop: true),
            // to enable saving comments in the tokenizer use the following line
            // Evaluator(regex: ".*", generator: { (r: Substring) in .Comment(r.trim()) }, pop: true)
            Evaluator(regex: ".*", generator: { _ in nil }, pop: true)
        ]
    }

    private static func stringEvaluators() -> [Evaluator] {
        return [
            Evaluator(regex: "\"", generator: { _ in nil }, pop: true),
            Evaluator(regex: "([\\u0020-\\u0021\\u0023-\\u005B\\u005D-\\uFFFF]|\\\\\"|\\\\)+",
                generator: { (r: Substring) throws(TomlError) in
                    .Identifier(try String(r).replaceEscapeSequences())
                })
        ]
    }

    private static func literalStringEvaluators() -> [Evaluator] {
        return [
            Evaluator(regex: "'", generator: { _ in nil }, pop: true),
            Evaluator(regex: "([\\u0020-\\u0026\\u0028-\\uFFFF])+",
                generator: { (r: Substring) in .Identifier(String(r)) })
        ]
    }

    private static func multiLineStringEvaluators() -> [Evaluator] {
        let validUnicodeChars = "\\u0020-\\u0021\\u0023-\\uFFFF"
        return [
            Evaluator(regex: "\"\"\"", generator: { _ in nil }, pop: true),
            // Note: Does not allow multi-line strings that end with double qoutes.
            // This is a common limitation of a variety of parsers I have tested
            Evaluator(regex: "([\n" + validUnicodeChars + "]\"?\"?)*[\n" + validUnicodeChars + "]+",
                // Line continuations are resolved before trimming: a
                // continuation is a backslash followed by whitespace, and
                // trimming first destroys the whitespace that identifies it.
                // A string ending in `"""\<newline>   ` then reached
                // `replaceEscapeSequences` as a lone trailing backslash,
                // which only produced the right answer because an incomplete
                // escape used to be discarded in silence.
                generator: { (r: Substring) throws(TomlError) in
                    .Identifier(try String(r).stripLineContinuation().trim().replaceEscapeSequences())
                }, multiline: true)
        ]
    }

    private static func multiLineStringLiteralEvaluators() -> [Evaluator] {
        let validUnicodeChars = "\n\\u0020-\\u0026\\u0028-\\uFFFF"
        return [
            Evaluator(regex: "'''", generator: { _ in nil }, pop: true),
            Evaluator(regex: "([" + validUnicodeChars + "]'?'?)*[" + validUnicodeChars + "]+",
                generator: { (r: Substring) in .Identifier(String(r).trim()) }, multiline: true)
        ]
    }

    private static func tableNameEvaluators() -> [Evaluator] {
        let tableErrorStr = "Invalid table name declaration"
        return [
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
        let dateTimeStr = "\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}"
        let dateStr = "\\d{4}-\\d{2}-\\d{2}"
        let timeStr = "\\d{2}:\\d{2}:\\d{2}"

        return [
            // Offset Date-Time: RFC 3339 w/ fractional seconds and time offset
            Evaluator(regex: dateTimeStr + ".\\d+(Z|z|[-\\+]\\d{2}:\\d{2})", generator: {
                (r: Substring) throws(TomlError) in
                    if let date = Date(rfc3339String: String(r)) {
                        return Token.DateTime(date)
                    } else {
                        throw TomlError.invalidDateFormat("####-##-##T##:##:##.###+/-##:## (\(r))")
                    }
            }, pop: true),
            // Offset Date-Time: RFC 3339 w/o fractional seconds and time offset
            Evaluator(regex: dateTimeStr + "(Z|z|[-\\+]\\d{2}:\\d{2})", generator: {
                (r: Substring) throws(TomlError) in
                    if let date = Date(rfc3339String: String(r), fractionalSeconds: false) {
                        return Token.DateTime(date)
                    } else {
                        throw TomlError.invalidDateFormat("####-##-##T##:##:##+/-##:## (\(r))")
                    }
            }, pop: true),
            // Local Date-Time: w/ fractional seconds, no timezone
            Evaluator(regex: dateTimeStr + ".\\d+", generator: { (r: Substring) in
                return Token.LocalDateTime(String(r))
            }, pop: true),
            // Local Date-Time: w/o fractional seconds, no timezone
            Evaluator(regex: dateTimeStr, generator: { (r: Substring) in
                return Token.LocalDateTime(String(r))
            }, pop: true),
            // Local Time: w/ fractional seconds
            Evaluator(regex: timeStr + ".\\d+", generator: { (r: Substring) in
                return Token.LocalTime(String(r))
            }, pop: true),
            // Local Time: w/o fractional seconds
            Evaluator(regex: timeStr, generator: { (r: Substring) in
                return Token.LocalTime(String(r))
            }, pop: true),
            // Local Date: date only
            Evaluator(regex: dateStr, generator: { (r: Substring) in
                return Token.LocalDate(String(r))
            }, pop: true)
        ]
    }

    private static func stringValueEvaluators() -> [Evaluator] {
        return [
            // Multi-line string values (must come before single-line test)
            // Special case, empty multi-line string
            Evaluator(regex: "\"\"\"\"\"\"", generator: {_ in .Identifier("") }, pop: true),
            Evaluator(regex: "\"\"\"", generator: { _ in nil },
                push: ["multilineString"], pop: true),
            // Multi-line literal string values (must come before single-line test)
            Evaluator(regex: "'''", generator: { _ in nil },
                push: ["multilineLiteralString"], pop: true),
            // Special case, empty multi-line string literal
            Evaluator(regex: "''''''", generator: { _ in .Identifier("") },
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
            Evaluator(regex: "[-\\+]?[0-9][0-9_]*(\\.[0-9_]+)?[eE][-\\+]?[0-9_]+",
                generator: generator, pop:true),
            // Double values no exponent (with optional underscores)
            Evaluator(regex: "[-\\+]?[0-9][0-9_]*\\.[0-9_]+", generator: generator, pop: true),
        ]
    }

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

        return [
            // Hexadecimal integer values (with optional underscores)
            Evaluator(regex: "0x[0-9A-Fa-f_]+",
                generator: radixGenerator(prefix: 2, radix: 16, name: "hexadecimal"), pop: true),
            // Octal integer values (with optional underscores)
            Evaluator(regex: "0o[0-7_]+",
                generator: radixGenerator(prefix: 2, radix: 8, name: "octal"), pop: true),
            // Binary integer values (with optional underscores)
            Evaluator(regex: "0b[01_]+",
                generator: radixGenerator(prefix: 2, radix: 2, name: "binary"), pop: true),
            // Decimal integer values (with optional underscores)
            Evaluator(regex: "[-\\+]?[0-9][0-9_]*",
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
            }, push: ["array", "array"], pop: true),
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

    private static func valueEvaluators() -> [Evaluator] {
        let typeEvaluators = stringValueEvaluators() + dateValueEvaluators() +
            specialFloatValueEvaluators() + doubleValueEvaluators() + intValueEvaluators() + booleanValueEvaluators()

        return whitespaceValueEvaluators() + arrayValueEvaluators() +
            inlineTableValueEvaluators() + typeEvaluators
    }

    private static func arrayEvaluators() -> [Evaluator] {
        return [
            // Ignore white-space
            Evaluator(regex: "[ \n\t]", generator: { _ in nil }),

            // Comments
            Evaluator(regex: "#", generator: { _ in nil }, push: ["comment"]),

            // Arrays
            Evaluator(regex: "\\[", generator: { _ in .ArrayBegin }, push: ["array"]),
            Evaluator(regex: "\\]", generator: { _ in .ArrayEnd }, pop: true),
            Evaluator(regex: ",", generator: { _ in nil }, push: ["array"]),
        ] + valueEvaluators()
    }

    private static func stringKeyEvaluator() -> [Evaluator] {
        let validUnicodeChars = "\\u0020-\\u0021\\u0023-\\u005B\\u005D-\\uFFFF"
        let bareKeyPattern = "[a-zA-Z0-9_-]+"

        // Simple dotted key pattern: only bare keys separated by dots (no quoted parts for now)
        let simpleDottedPattern = bareKeyPattern + "([ \t]*\\.[ \t]*" + bareKeyPattern + ")+[ \t]*="

        return [
            // string key (quoted keys take precedence)
            Evaluator(regex: "\"([" + validUnicodeChars + "]|\\\\\"|\\\\)+\"[ \t]*=",
                generator: { (r: Substring) throws(TomlError) in
                    .Key(try trimStringIdentifier(r, "\"").replaceEscapeSequences())
                },
                push: ["value"]),
            // literal string key
            Evaluator(regex: "'([\\u0020-\\u0026\\u0028-\\uFFFF])+'[ \t]*=",
                generator: { (r: Substring) in .Key(trimStringIdentifier(r, "'")) },
                push: ["value"]),
            // dotted key (must come after quoted keys but before simple keys)
            Evaluator(regex: simpleDottedPattern,
                generator: { (r: Substring) in
                    // Remove the trailing '=' and trim
                    .Key(String(r.dropLast()).trim())
                },
                push: ["value"]),
            // bare key
            Evaluator(regex: bareKeyPattern + "[ \t]*=",
                generator: { (r: Substring) in
                    .Key(String(r.dropLast()).trim())
                },
                push: ["value"]),
        ]
    }

    private static func inlineTableEvaluators() -> [Evaluator] {
        return [
            // Ignore white-space and commas
            Evaluator(regex: "[ \t,]", generator: { _ in nil }),
            // inline-table
            Evaluator(regex: "\\{", generator: { _ in .InlineTableBegin }, push: ["inlineTable"]),
            Evaluator(regex: "\\}", generator: { _ in .InlineTableEnd }, pop: true),
        ] + stringKeyEvaluator()
    }

    private static func rootEvaluators() -> [Evaluator] {
        return [
            // Ignore white-space
            Evaluator(regex: "[ \t\r\n]", generator: { _ in nil }),
            // Comments
            Evaluator(regex: "#", generator: { _ in nil }, push: ["comment"]),
        ] + stringKeyEvaluator() + [
            // Array of tables (must come before table)
            Evaluator(regex: "\\[\\[", generator: { _ in .TableArrayBegin }, push: ["tableArray"]),
            // Tables
            Evaluator(regex: "\\[", generator: { _ in .TableBegin }, push: ["tableName"]),
        ]
    }
}
