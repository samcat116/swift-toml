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

// MARK: Parse

class Parser {
    var keyPath: [String] = []
    var currentKey = "."
    var declaredTables = Set<String>()
    var toml: Toml = Toml()

    // MARK: Initializers

    convenience init(toml: Toml) {
        self.init()
        self.toml = toml
    }

    // MARK: Parsing

    public func parse(string: String) throws {
        // Convert input into tokens
        let lexer = Lexer(input: string, grammar: Grammar().grammar)
        let tokens = try lexer.tokenize()
        try parse(tokens: tokens)
    }
    
    /**
        Parse a dotted key into its components, handling quoted sections
        
        - Parameter key: The dotted key string (e.g., "a.b.c" or "a.'b.c'.d")
        - Returns: Array of key components
    */
    private func parseDottedKey(_ key: String) -> [String] {
        // First check if this could be a dotted key with spaces (e.g., "a . b . c")
        // These are valid bare dotted keys in TOML
        let keyWithoutSpacesAroundDots = key.replacingOccurrences(of: " . ", with: ".")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: ". ", with: ".")
        
        // Check if after removing spaces around dots, we have a valid bare key pattern
        let bareKeyComponentPattern = "^[a-zA-Z0-9_-]+(\\.[a-zA-Z0-9_-]+)*$"
        if let _ = keyWithoutSpacesAroundDots.range(of: bareKeyComponentPattern, options: .regularExpression) {
            // This is a dotted key (possibly with spaces around dots)
            // Continue with normal parsing
        } else {
            // This key contains special characters that would require quoting,
            // so it was likely a quoted key - return as single component
            return [key]
        }
        
        var components: [String] = []
        var current = ""
        var inQuotes = false
        var quoteChar: Character? = nil
        var escaped = false
        var i = key.startIndex
        
        while i < key.endIndex {
            let char = key[i]
            
            if escaped {
                current.append(char)
                escaped = false
            } else if char == "\\" && inQuotes {
                current.append(char)
                escaped = true
            } else if (char == "\"" || char == "'") && !inQuotes {
                // Starting a quoted section
                inQuotes = true
                quoteChar = char
            } else if char == quoteChar && inQuotes {
                // Ending a quoted section
                inQuotes = false
                quoteChar = nil
            } else if char == "." && !inQuotes {
                // Found a dot separator outside quotes
                let trimmed = current.trim()
                if !trimmed.isEmpty {
                    // Remove quotes if the entire component is quoted
                    if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
                       (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
                        let start = trimmed.index(after: trimmed.startIndex)
                        let end = trimmed.index(before: trimmed.endIndex)
                        components.append(String(trimmed[start..<end]))
                    } else {
                        components.append(trimmed)
                    }
                }
                current = ""
            } else {
                current.append(char)
            }
            
            i = key.index(after: i)
        }
        
        // Don't forget the last component
        let trimmed = current.trim()
        if !trimmed.isEmpty {
            // Remove quotes if the entire component is quoted
            if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
               (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
                let start = trimmed.index(after: trimmed.startIndex)
                let end = trimmed.index(before: trimmed.endIndex)
                components.append(String(trimmed[start..<end]))
            } else {
                components.append(trimmed)
            }
        }
        
        return components.isEmpty ? [key] : components
    }

    /**
        Parse a TOML token stream construct a dictionary.

        - Parameter tokens: Token stream describing a TOML data structure
    */
    private func parse(tokens: [Token]) throws {
        // A dispatch table for parsing TOML tables
        let TokenMap: [Token: (Token, inout [Token]) throws -> ()] = [
            .Identifier("1"): setValue,
            .IntegerNumber(1): setValue,
            .DoubleNumber(1.0): setValue,
            .Boolean(true): setValue,
            .DateTime(Date()): setValue,
            .LocalDate("1979-05-27"): setValue,
            .LocalTime("07:32:00"): setValue,
            .LocalDateTime("1979-05-27T07:32:00"): setValue,
            .TableBegin: setTable,
            .ArrayBegin: setArray,
            .TableArrayBegin: setTableArray,
            .InlineTableBegin: setInlineTable
        ]

        // Convert tokens to values in the Toml
        var myTokens = tokens

        while !myTokens.isEmpty {
            let token = myTokens.remove(at: 0)
            if case .Key(let val) = token {
                // Handle dotted keys by parsing them into components
                let keyComponents = parseDottedKey(val)
                if keyComponents.count > 1 {
                    // For dotted keys, we need to set up the key path
                    currentKey = keyComponents.last!
                    // Create nested tables if needed
                    var currentPath = keyPath  // Start with current table context
                    for i in 0..<(keyComponents.count - 1) {
                        currentPath.append(keyComponents[i])
                        if !toml.hasTable(currentPath) {
                            toml.setTable(key: currentPath)
                        }
                    }
                    // Store the previous keyPath to restore later
                    let savedKeyPath = keyPath
                    keyPath = currentPath
                    
                    // Process the next token (the value)
                    if !myTokens.isEmpty {
                        let valueToken = myTokens.remove(at: 0)
                        try TokenMap[valueToken]!(valueToken, &myTokens)
                    }
                    
                    // Restore the keyPath
                    keyPath = savedKeyPath
                } else {
                    currentKey = val
                }
            } else {
                try TokenMap[token]!(token, &myTokens)
            }
        }
    }

    /**
        Given a TOML token stream construct an array.

        - Parameter tokens: Token stream describing array

        - Returns: Array populated with values from token stream
    */
    private func parse(tokens: inout [Token]) throws -> [Any] {
        var array: [Any] = [Any]()

        while !tokens.isEmpty {
            let token = tokens.remove(at: 0)
            switch token {
                case .Identifier(let val):
                    array.append(val)
                case .IntegerNumber(let val):
                    array.append(val)
                case .DoubleNumber(let val):
                    array.append(val)
                case .Boolean(let val):
                    array.append(val)
                case .DateTime(let val):
                    array.append(val)
                case .LocalDate(let val):
                    array.append(val)
                case .LocalTime(let val):
                    array.append(val)
                case .LocalDateTime(let val):
                    array.append(val)
                case .InlineTableBegin:
                    array.append(try processInlineTable(tokens: &tokens))
                case .ArrayBegin:
                    var wrap = ArrayWrapper(array: array)
                    try checkAndSetArray(check: parse(tokens: &tokens), key: [""], out: &wrap)
                    array = wrap.array
                default:
                    return array
            }
        }

        return array
    }

    private func processInlineTable(tokens: inout [Token]) throws -> Toml {
        let tableTokens = extractTableTokens(tokens: &tokens, inline: true)
        let tableParser = Parser()
        try tableParser.parse(tokens: tableTokens)
        return tableParser.toml
    }

    /**
        Given a value token set its value in the `table`

        - Parameter currToken: A value token that is currently being parsed
        - Parameter tokens: Array of remaining tokens in the stream
    */
    private func setValue(currToken: Token, tokens: inout [Token]) throws {
        var key = keyPath
        key.append(currentKey)

        if toml.hasKey(key: key) {
            throw TomlError.DuplicateKey(String(describing: key))
        }

        toml.set(value: currToken.value as Any, for: key)
    }

    /**
        Given a table extract all associated tokens from the stream and create
        a new dictionary.

        - Parameter currToken: A `Token.TableBegin` token
        - Parameter table: Parent table to save resulting table to
    */
    private func setTable(currToken: Token, tokens: inout [Token]) throws {
        var tableExists = false
        var emptyTableSep = false
        // clear out the keyPath
        keyPath.removeAll()

        while !tokens.isEmpty {
            let subToken = tokens.remove(at: 0)
            if case .TableEnd = subToken {
                if keyPath.count < 1 {
                    throw TomlError.SyntaxError("Table name must not be blank")
                }

                let keyPathStr = String(describing: keyPath)
                if toml.hasKey(key: keyPath, includeTables: false) || declaredTables.contains(keyPathStr) {
                    throw TomlError.DuplicateKey(String(describing: keyPath))
                }

                declaredTables.insert(keyPathStr)
                let tableTokens = extractTableTokens(tokens: &tokens)
                try parse(tokens: tableTokens)
                tableExists = true
                break
            } else if case .TableSep = subToken {
                if emptyTableSep {
                    throw TomlError.SyntaxError("Must not have un-named implicit tables")
                }
                emptyTableSep = true
            } else if case .Identifier(let val) = subToken {
                emptyTableSep = false
                keyPath.append(val)
                toml.setTable(key: keyPath)
            }
        }

        if !tableExists {
            throw TomlError.SyntaxError("Table must contain at least a closing bracket")
        }
    }

    private func setTableArray(currToken: Token, tokens: inout [Token]) throws {
        // clear out the keyPath
        keyPath.removeAll()

        tableLoop: while !tokens.isEmpty {
            let subToken = tokens.remove(at: 0)
            if case .TableArrayEnd = subToken {
                if keyPath.count < 1 {
                    throw TomlError.SyntaxError("Table array name must not be blank")
                }

                let tableTokens = getTableTokens(keyPath: keyPath, tokens: &tokens)

                if toml.hasKey(key: keyPath) {
                    var arr: [Toml] = toml.array(keyPath)!
                    let tableParser = Parser()
                    try tableParser.parse(tokens: tableTokens)
                    arr.append(tableParser.toml)
                    toml.set(value: arr, for: keyPath)
                } else {
                    let tableParser = Parser()
                    try tableParser.parse(tokens: tableTokens)
                    toml.set(value: [tableParser.toml], for: keyPath)
                }
                break tableLoop
            } else if case .Identifier(let val) = subToken {
                keyPath.append(val)
            }
        }
    }

    /**
        Given an inline table extract all associated tokens from the stream
        and create a new dictionary.

        - Parameter currToken: A `Token.InlineTableBegin` token
        - Parameter table: Parent table to save resulting inline table to
    */
    private func setInlineTable(currToken: Token, tokens: inout [Token]) throws {
        keyPath.append(currentKey)

        let tableTokens = extractTableTokens(tokens: &tokens, inline: true)
        try parse(tokens: tableTokens)

        toml.setTable(key: keyPath)

        // This was an inline table so remove from keyPath
        keyPath.removeLast()
    }

    /**
        Given an array save it to the parent table

        - Parameter currToken: A `Token.ArrayBegin` token
        - Parameter table: Parent table to save resulting inline table to
    */
    private func setArray(currToken: Token, tokens: inout [Token]) throws {
        let arr: [Any] = try parse(tokens: &tokens)

        var myKeyPath = keyPath
        myKeyPath.append(currentKey)

        // allow empty arrays
        if arr.isEmpty {
            toml.set(value: arr, for: myKeyPath)
            return
        }

        try checkAndSetArray(check: arr, key: myKeyPath, out: &toml)
    }
}
