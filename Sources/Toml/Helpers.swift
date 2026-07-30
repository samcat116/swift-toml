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

final class ArrayWrapper: SetValueProtocol {
    var array: [Any]

    init(array: [Any]) {
        self.array = array
    }

    func set(value: Any, for: [String]) {
        array.append(value)
    }
}

/**
    Store an array, narrowing it to a homogeneous element type where it has
    one.

    An array whose members are all `Int` is stored as `[Int]`, so that
    `array("key") as [Int]?` succeeds. TOML has allowed arrays to mix types
    since 1.0, so an array that does not narrow is stored as `[Any]` rather
    than rejected -- this used to throw `mixedArrayType`, which made
    `numbers = [ 0.1, 1 ]` from the specification a parse error.

    - Parameter check: Input array to store
    - Parameter key: Key path the array will be stored at
    - Parameter out: Destination to store the result in
*/
func checkAndSetArray<T: SetValueProtocol>(check: [Any], key: [String], out: inout T) {
    // allow empty arrays
    guard let first = check.first else {
        out.set(value: check, for: key)
        return
    }

    switch first {
        case is Int:
            out.set(value: (check as? [Int]).map { $0 as Any } ?? check, for: key)
        case is Double:
            out.set(value: (check as? [Double]).map { $0 as Any } ?? check, for: key)
        case is String:
            out.set(value: (check as? [String]).map { $0 as Any } ?? check, for: key)
        case is Bool:
            out.set(value: (check as? [Bool]).map { $0 as Any } ?? check, for: key)
        case is Date:
            out.set(value: (check as? [Date]).map { $0 as Any } ?? check, for: key)
        case is TomlDate:
            out.set(value: (check as? [TomlDate]).map { $0 as Any } ?? check, for: key)
        default:
            // array of arrays, or of tables: leave as any
            out.set(value: check, for: key)
    }
}

/**
    Strip the surrounding quotes and the trailing `=` from a quoted key.

    - Parameter input: The matched key text, e.g. `"my key" =`
    - Parameter quote: The quote character used, `"` or `'`
*/
func trimStringIdentifier(_ input: Substring, _ quote: Character = "\"") -> String {
    // The lexer only produces this text by matching a quoted key followed by
    // `=`, so the quotes are guaranteed to be present. Locating them directly
    // avoids running a second regex over the input just to find them.
    guard let open = input.firstIndex(of: quote),
          let close = input.lastIndex(of: quote),
          open < close else {
        return String(input)
    }
    return String(input[input.index(after: open)..<close])
}

/**
    Split the text of a key declaration into its dotted components.

    Quotes are stripped and escape sequences inside basic-string segments are
    resolved, so the result is the sequence of names the key denotes. Doing
    this here, while the quoting is still visible, is what lets `"a.b" = 1`
    (one component) be told apart from `a."b" = 1` (two) -- once the quotes
    are gone the two are indistinguishable.

    - Parameter input: The matched key text, including the trailing `=`
*/
func splitDottedKey(_ input: Substring) throws(TomlError) -> [String] {
    var chars = Array(input)
    if chars.last == "=" {
        chars.removeLast()
    }

    var components = [String]()
    var index = 0
    var expectSegment = true

    while index < chars.count {
        while index < chars.count, chars[index] == " " || chars[index] == "\t" {
            index += 1
        }
        guard index < chars.count else { break }

        let char = chars[index]

        if char == "." {
            guard !expectSegment else {
                throw TomlError.syntaxError("Key has an empty component: \(input)")
            }
            expectSegment = true
            index += 1
            continue
        }

        guard expectSegment else {
            throw TomlError.syntaxError("Key components must be separated by '.': \(input)")
        }

        if char == "\"" || char == "'" {
            let quote = char
            index += 1
            var raw = ""
            var closed = false

            while index < chars.count {
                let current = chars[index]
                // Only basic strings have escapes; in a literal string a
                // backslash is just a backslash.
                if quote == "\"", current == "\\", index + 1 < chars.count {
                    raw.append(current)
                    raw.append(chars[index + 1])
                    index += 2
                    continue
                }
                if current == quote {
                    closed = true
                    index += 1
                    break
                }
                raw.append(current)
                index += 1
            }

            guard closed else {
                throw TomlError.syntaxError("Unterminated quoted key: \(input)")
            }
            components.append(quote == "\"" ? try raw.replaceEscapeSequences() : raw)
        } else {
            var raw = ""
            while index < chars.count, chars[index] != ".",
                  chars[index] != " ", chars[index] != "\t" {
                raw.append(chars[index])
                index += 1
            }
            components.append(raw)
        }

        expectSegment = false
    }

    guard !components.isEmpty, !expectSegment else {
        throw TomlError.syntaxError("Invalid key: \(input)")
    }

    return components
}

/**
    Check that an inline table's entries are separated by commas, and return
    the tokens with those commas removed.

    Entries are separated by exactly one comma, and TOML 1.1.0 allows one
    after the last entry. Commas belonging to a nested array or inline table
    are that container's business, so only the outermost level is considered.

    - Parameter tokens: The tokens between the braces
*/
func inlineTableEntryTokens(_ tokens: [Token]) throws(TomlError) -> [Token] {
    var result = [Token]()
    result.reserveCapacity(tokens.count)

    var depth = 0
    var expectKey = true

    for token in tokens {
        switch token {
        case .ArrayBegin, .InlineTableBegin:
            depth += 1
        case .ArrayEnd, .InlineTableEnd:
            depth -= 1
        case .Comma where depth == 0:
            guard !expectKey else {
                throw TomlError.syntaxError("Unexpected ',' in inline table")
            }
            expectKey = true
            continue  // the separator itself is not part of any entry
        case .Key where depth == 0:
            guard expectKey else {
                throw TomlError.syntaxError("Inline table entries must be separated by ','")
            }
            expectKey = false
        default:
            break
        }

        result.append(token)
    }

    return result
}

/**
    Drop the closing delimiter from a matched multi-line string.

    The match ends in a run of three to five delimiter characters; exactly the
    last three close the string, so everything before them is content.
*/
func multiLineStringBody(_ matched: Substring) -> String {
    String(matched.dropLast(3))
}

func getKeyPathFromTable(tokens: ArraySlice<Token>) -> [String] {
    var subKeyPath = [String]()
    subKeyPathLoop: for token in tokens {
        switch token {
            case .Identifier(let val):
                subKeyPath.append(val)
            case .TableSep, .TableArrayBegin, .TableBegin:
                continue
            default:
                break subKeyPathLoop
        }
    }

    return subKeyPath
}

func consumeTableIdentifierTokens(tableTokens: inout [Token], tokens: inout ArraySlice<Token>) {
    while let nestedToken = tokens.popFirst() {
        tableTokens.append(nestedToken)
        if case .TableEnd = nestedToken {
            break
        } else if case .TableArrayEnd = nestedToken {
            break
        }
    }
}

func getTableTokens(keyPath: [String], tokens: inout ArraySlice<Token>) throws(TomlError) -> [Token] {
    guard !keyPath.isEmpty else {
        throw TomlError.syntaxError("Table name must not be blank")
    }

    var tableTokens = [Token]()
    nestedTableLoop: while let tableToken = tokens.first {
        // need to include sub tables
        switch tableToken {
            case .TableBegin, .TableArrayBegin:
                // get the key path of the new table
                let subKeyPath = getKeyPathFromTable(tokens: tokens)

                // A table belongs to this one only if its name extends this
                // one's: `[[a.b]]` followed by `[a.b.c]` nests, `[[a.b]]`
                // followed by another `[[a.b]]` does not. Comparing only the
                // first component made a repeated `[[a.b]]` look like a child
                // of the element before it, so the second element was parsed
                // into the first instead of appended beside it.
                //
                // An empty sub key path means the declaration was truncated
                // (for example a trailing "["); indexing it unconditionally
                // used to trap.
                guard subKeyPath.count > keyPath.count,
                      subKeyPath.starts(with: keyPath) else {
                    break nestedTableLoop
                }

                // this table should be included because it's a
                // nested table

                // .TableBegin || .TableArrayBegin
                tokens.removeFirst()
                tableTokens.append(tableToken)

                // Drop the part of the name this table already accounts for:
                // its Identifier and the .TableSep after it, once per
                // component. Malformed input can end the stream early, so
                // these are dropped rather than unconditionally removed.
                for _ in 0..<keyPath.count {
                    _ = tokens.popFirst() // Identifier
                    _ = tokens.popFirst() // .TableSep
                }

                consumeTableIdentifierTokens(tableTokens: &tableTokens, tokens: &tokens)
            default:
                tokens.removeFirst()
                tableTokens.append(tableToken)
        }
    }

    return tableTokens
}

/**
    Extract the tokens belonging to a single table from the stream.

    - Parameter tokens: Remaining tokens, consumed in place
    - Parameter inline: Whether this is an inline (brace-delimited) table
*/
func extractTableTokens(tokens: inout ArraySlice<Token>, inline: Bool = false) -> [Token] {
    var tableTokens = [Token]()

    if inline {
        // Inline tables nest, so the extent of this one runs to its *matching*
        // closing brace. Stopping at the first `InlineTableEnd` left the extra
        // closing braces of a nested table such as `a = {b = {c = 1}}` in the
        // stream, where the top-level parse loop then met a token it had no
        // handler for and trapped.
        var depth = 1
        while let tableToken = tokens.popFirst() {
            if case .InlineTableBegin = tableToken {
                depth += 1
            } else if case .InlineTableEnd = tableToken {
                depth -= 1
                if depth == 0 {
                    break
                }
            }
            tableTokens.append(tableToken)
        }
        return tableTokens
    }

    while let tableToken = tokens.first {
        if case .TableBegin = tableToken {
            break
        } else if case .TableArrayBegin = tableToken {
            break
        }

        tokens.removeFirst()
        tableTokens.append(tableToken)
    }

    return tableTokens
}
