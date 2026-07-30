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
    Utility function to cast an array to a given type or throw an error

    - Parameter check: Input array to cast to type T
    - Parameter key: Key path the array will be stored at
    - Parameter out: Array to store result in

    - Throws: `TomlError.mixedArrayType` if array cannot be cast to appropriate type
*/
func checkAndSetArray<T: SetValueProtocol>(check: [Any], key: [String], out: inout T) throws(TomlError) {
    // allow empty arrays
    guard let first = check.first else {
        out.set(value: check, for: key)
        return
    }

    // convert array to proper type
    switch first {
        case is Int:
            if let typedArray = check as? [Int] {
                out.set(value: typedArray, for: key)
            } else {
                throw TomlError.mixedArrayType("Int")
            }
        case is Double:
            if let typedArray = check as? [Double] {
                out.set(value: typedArray, for: key)
            } else {
                throw TomlError.mixedArrayType("Double")
            }
        case is String:
            if let typedArray = check as? [String] {
                out.set(value: typedArray, for: key)
            } else {
                throw TomlError.mixedArrayType("String")
            }
        case is Bool:
            if let typedArray = check as? [Bool] {
                out.set(value: typedArray, for: key)
            } else {
                throw TomlError.mixedArrayType("Bool")
            }
        case is Date:
            if let typedArray = check as? [Date] {
                out.set(value: typedArray, for: key)
            } else {
                throw TomlError.mixedArrayType("Date")
            }
        default:
            // array of arrays leave as any
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
    guard let root = keyPath.first else {
        throw TomlError.syntaxError("Table name must not be blank")
    }

    var tableTokens = [Token]()
    nestedTableLoop: while let tableToken = tokens.first {
        // need to include sub tables
        switch tableToken {
            case .TableBegin, .TableArrayBegin:
                // get the key path of the new table
                let subKeyPath = getKeyPathFromTable(tokens: tokens)

                // If the new table is nested within the current one
                // include it, otherwise we are finished.
                //
                // An empty sub key path means the declaration was truncated
                // (for example a trailing "["); indexing it unconditionally
                // used to trap.
                guard let subRoot = subKeyPath.first, subKeyPath.count > 1 else {
                    // top-level or incomplete - break
                    break nestedTableLoop
                }

                if subRoot != root {
                    // nested table but not part of this table group
                    break nestedTableLoop
                }

                // this table should be included because it's a
                // nested table

                // .TableBegin || .TableArrayBegin
                tokens.removeFirst()
                tableTokens.append(tableToken)

                // skip first name: the Identifier and the .TableSep that
                // follows it. Malformed input can end the stream early, so
                // these are dropped rather than unconditionally removed.
                _ = tokens.popFirst() // Identifier
                _ = tokens.popFirst() // .TableSep

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
