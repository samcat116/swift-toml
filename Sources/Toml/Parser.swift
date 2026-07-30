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

/// Matches a bare dotted key, optionally with whitespace around the dots.
private let bareDottedKeyPattern = Pattern("[a-zA-Z0-9_-]+([ \t]*\\.[ \t]*[a-zA-Z0-9_-]+)*$")

struct Parser {
    var keyPath: [String] = []
    var currentKey = "."
    var declaredTables = Set<Path>()
    var toml: Toml = Toml()

    // MARK: Initializers

    init() {}

    init(toml: Toml) {
        self.toml = toml
    }

    // MARK: Parsing

    mutating func parse(string: String) throws(TomlError) {
        // Convert input into tokens
        let lexer = Lexer(input: string)
        let tokens = try lexer.tokenize()
        try parse(tokens: tokens)
    }

    /**
        Parse a dotted key into its components, handling quoted sections

        - Parameter key: The dotted key string (e.g., "a.b.c" or "a.'b.c'.d")
        - Returns: Array of key components
    */
    private func parseDottedKey(_ key: String) -> [String] {
        // A key that is not a bare dotted key came from a quoted key, whose
        // dots are part of the name rather than separators.
        guard bareDottedKeyPattern.prefixMatch(in: key[...]) != nil else {
            return [key]
        }

        var components: [String] = []
        var current = ""
        var inQuotes = false
        var quoteChar: Character?
        var escaped = false

        func appendCurrent() {
            let trimmed = current.trim()
            guard !trimmed.isEmpty else { return }
            // Remove quotes if the entire component is quoted
            if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
               (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")),
               trimmed.count >= 2 {
                components.append(String(trimmed.dropFirst().dropLast()))
            } else {
                components.append(trimmed)
            }
        }

        for char in key {
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
                appendCurrent()
                current = ""
            } else {
                current.append(char)
            }
        }

        appendCurrent()

        return components.isEmpty ? [key] : components
    }

    /**
        Parse a TOML token stream construct a dictionary.

        - Parameter tokens: Token stream describing a TOML data structure
    */
    private mutating func parse(tokens: [Token]) throws(TomlError) {
        // Convert tokens to values in the Toml
        var myTokens = tokens[...]

        while let token = myTokens.popFirst() {
            if case .Key(let val) = token {
                // Handle dotted keys by parsing them into components
                let keyComponents = parseDottedKey(val)
                if keyComponents.count > 1 {
                    // For dotted keys, we need to set up the key path
                    currentKey = keyComponents[keyComponents.count - 1]
                    // Create nested tables if needed
                    var currentPath = keyPath  // Start with current table context
                    for component in keyComponents.dropLast() {
                        currentPath.append(component)
                        if !toml.hasTable(currentPath) {
                            toml.setTable(key: currentPath)
                        }
                    }
                    // Store the previous keyPath to restore later
                    let savedKeyPath = keyPath
                    keyPath = currentPath

                    // Process the next token (the value)
                    if let valueToken = myTokens.popFirst() {
                        try dispatch(valueToken, &myTokens)
                    }

                    // Restore the keyPath
                    keyPath = savedKeyPath
                } else {
                    currentKey = val
                }
            } else {
                try dispatch(token, &myTokens)
            }
        }
    }

    /**
        Route a token to the routine that consumes it.

        Tokens that only ever appear as the closing half of a construct
        (`]`, `}`, and the table-name terminators) are consumed by the routine
        that handled the opening half. Reaching one here means the stream is
        unbalanced, which malformed input can produce, so it is reported as a
        syntax error. Previously this was a force-unwrapped dictionary lookup
        and crashed the process instead.
    */
    private mutating func dispatch(_ token: Token, _ tokens: inout ArraySlice<Token>) throws(TomlError) {
        switch token {
        case .Identifier, .IntegerNumber, .DoubleNumber, .Boolean,
             .DateTime, .LocalDate, .LocalTime, .LocalDateTime:
            try setValue(currToken: token)
        case .TableBegin:
            try setTable(tokens: &tokens)
        case .ArrayBegin:
            try setArray(tokens: &tokens)
        case .TableArrayBegin:
            try setTableArray(tokens: &tokens)
        case .InlineTableBegin:
            try setInlineTable(tokens: &tokens)
        case .Key:
            // Handled by the caller.
            throw TomlError.syntaxError("Unexpected key: \(token)")
        case .ArrayEnd, .TableArrayEnd, .InlineTableEnd, .TableEnd, .TableSep, .Comment:
            throw TomlError.syntaxError("Unexpected token: \(token)")
        }
    }

    /**
        Given a TOML token stream construct an array.

        - Parameter tokens: Token stream describing array

        - Returns: Array populated with values from token stream
    */
    private mutating func parse(tokens: inout ArraySlice<Token>) throws(TomlError) -> [Any] {
        var array: [Any] = [Any]()

        while let token = tokens.popFirst() {
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

    private func processInlineTable(tokens: inout ArraySlice<Token>) throws(TomlError) -> Toml {
        let tableTokens = extractTableTokens(tokens: &tokens, inline: true)
        var tableParser = Parser()
        try tableParser.parse(tokens: tableTokens)
        return tableParser.toml
    }

    /**
        Given a value token set its value in the `table`

        - Parameter currToken: A value token that is currently being parsed
    */
    private func setValue(currToken: Token) throws(TomlError) {
        var key = keyPath
        key.append(currentKey)

        if toml.hasKey(key: key) {
            throw TomlError.duplicateKey(String(describing: key))
        }

        toml.set(value: currToken.value as Any, for: key)
    }

    /**
        Given a table extract all associated tokens from the stream and create
        a new dictionary.

        - Parameter tokens: Array of remaining tokens in the stream
    */
    private mutating func setTable(tokens: inout ArraySlice<Token>) throws(TomlError) {
        var tableExists = false
        var emptyTableSep = false
        // clear out the keyPath
        keyPath.removeAll()

        while let subToken = tokens.popFirst() {
            if case .TableEnd = subToken {
                if keyPath.isEmpty {
                    throw TomlError.syntaxError("Table name must not be blank")
                }

                let path = Path(keyPath)
                if toml.hasKey(key: keyPath, includeTables: false) || declaredTables.contains(path) {
                    throw TomlError.duplicateKey(String(describing: keyPath))
                }

                declaredTables.insert(path)
                let tableTokens = extractTableTokens(tokens: &tokens)
                try parse(tokens: tableTokens)
                tableExists = true
                break
            } else if case .TableSep = subToken {
                if emptyTableSep {
                    throw TomlError.syntaxError("Must not have un-named implicit tables")
                }
                emptyTableSep = true
            } else if case .Identifier(let val) = subToken {
                emptyTableSep = false
                keyPath.append(val)
                toml.setTable(key: keyPath)
            }
        }

        if !tableExists {
            throw TomlError.syntaxError("Table must contain at least a closing bracket")
        }
    }

    private mutating func setTableArray(tokens: inout ArraySlice<Token>) throws(TomlError) {
        // clear out the keyPath
        keyPath.removeAll()

        var sawEnd = false

        tableLoop: while let subToken = tokens.popFirst() {
            if case .TableArrayEnd = subToken {
                if keyPath.isEmpty {
                    throw TomlError.syntaxError("Table array name must not be blank")
                }

                let tableTokens = try getTableTokens(keyPath: keyPath, tokens: &tokens)

                var tableParser = Parser()
                try tableParser.parse(tokens: tableTokens)

                if toml.hasKey(key: keyPath) {
                    guard var arr: [Toml] = toml.array(keyPath) else {
                        throw TomlError.duplicateKey(String(describing: keyPath))
                    }
                    arr.append(tableParser.toml)
                    toml.set(value: arr, for: keyPath)
                } else {
                    toml.set(value: [tableParser.toml], for: keyPath)
                }
                sawEnd = true
                break tableLoop
            } else if case .Identifier(let val) = subToken {
                keyPath.append(val)
            }
        }

        // A truncated declaration such as "[[a.b" used to be accepted
        // silently, producing an empty document.
        if !sawEnd {
            throw TomlError.syntaxError("Table array must contain a closing bracket")
        }
    }

    /**
        Given an inline table extract all associated tokens from the stream
        and create a new dictionary.

        - Parameter tokens: Array of remaining tokens in the stream
    */
    private mutating func setInlineTable(tokens: inout ArraySlice<Token>) throws(TomlError) {
        keyPath.append(currentKey)

        let tableTokens = extractTableTokens(tokens: &tokens, inline: true)
        try parse(tokens: tableTokens)

        toml.setTable(key: keyPath)

        // This was an inline table so remove from keyPath
        keyPath.removeLast()
    }

    /**
        Given an array save it to the parent table

        - Parameter tokens: Array of remaining tokens in the stream
    */
    private mutating func setArray(tokens: inout ArraySlice<Token>) throws(TomlError) {
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
