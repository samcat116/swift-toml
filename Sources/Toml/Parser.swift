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

struct Parser {
    var keyPath: [String] = []
    var currentKey = "."
    var declaredTables = Set<Path>()
    /// Tables brought into being by a dotted key, such as `a` in `a.b = 1`.
    /// A later `[a]` header may not reopen one of these.
    var dottedKeyTables = Set<Path>()
    /// Tables written as `{ ... }`. These are closed for good: nothing may
    /// add a key to one, whether by header or by dotted key.
    var inlineTables = Set<Path>()
    /// Paths that hold an array of tables, and so may be appended to by a
    /// further `[[...]]` -- unlike a path that holds an ordinary array.
    var tableArrays = Set<Path>()
    /// Tables that exist only because something below them was named, as
    /// `albums` does after `[[albums.songs]]`.
    var implicitTables = Set<Path>()
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
        Parse a TOML token stream construct a dictionary.

        - Parameter tokens: Token stream describing a TOML data structure
    */
    private mutating func parse(tokens: [Token]) throws(TomlError) {
        // Convert tokens to values in the Toml
        var myTokens = tokens[...]

        while let token = myTokens.popFirst() {
            if case .Key(let keyComponents) = token {
                if keyComponents.count > 1 {
                    // For dotted keys, we need to set up the key path
                    currentKey = keyComponents[keyComponents.count - 1]
                    // Create nested tables if needed
                    var currentPath = keyPath  // Start with current table context
                    for component in keyComponents.dropLast() {
                        currentPath.append(component)

                        // Each name before the last must be a table this key
                        // may define or extend, which it is not if it already
                        // holds a value (`a = 1` then `a.b = 2`), if it holds
                        // an inline table, which is closed, or if a header
                        // defined it -- `[a.b.c]` followed by `[a]` and
                        // `b.c.t = 1` reaches back into a finished table.
                        if toml.hasKey(key: currentPath, includeTables: false)
                            || inlineTables.contains(Path(currentPath))
                            || declaredTables.contains(Path(currentPath)) {
                            throw TomlError.duplicateKey(String(describing: currentPath))
                        }

                        dottedKeyTables.insert(Path(currentPath))
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
                } else if let only = keyComponents.first {
                    currentKey = only
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
        case .ArrayEnd, .TableArrayEnd, .InlineTableEnd, .TableEnd, .TableSep,
             .Comment, .Comma:
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
        // Values are separated by exactly one comma, with an optional one
        // after the last. This tracks whether the next token may be a value:
        // it may not be right after another value (`[1 2]`), and a comma may
        // not appear where a value is due (`[,]`, `[1,,2]`).
        var expectValue = true

        while let token = tokens.popFirst() {
            if case .Comma = token {
                guard !expectValue else {
                    throw TomlError.syntaxError("Unexpected ',' in array")
                }
                expectValue = true
                continue
            }

            if case .ArrayEnd = token {
                return array
            }

            guard expectValue else {
                throw TomlError.syntaxError("Array values must be separated by ','")
            }
            expectValue = false

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
                case .LocalDate, .LocalTime, .LocalDateTime:
                    // Carried as `TomlDate`, which the token knows how to build.
                    if let val = token.value {
                        array.append(val)
                    }
                case .InlineTableBegin:
                    array.append(try processInlineTable(tokens: &tokens))
                case .ArrayBegin:
                    var wrap = ArrayWrapper(array: array)
                    checkAndSetArray(check: try parse(tokens: &tokens), key: [""], out: &wrap)
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
        try tableParser.parse(tokens: try inlineTableEntryTokens(tableTokens))
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
        // Whitespace inside the brackets is allowed around the parts of the
        // name but not between two of them: `[ a . b ]` names `a.b`, while
        // `[a b]` is an error. The lexer discards the whitespace, so the
        // missing separator is caught here, by the two names arriving in a
        // row.
        var sawIdentifier = false
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

                // A table that a dotted key already defined is closed to a
                // header, and an inline table -- or anything inside one -- is
                // closed to everything.
                if dottedKeyTables.contains(path) {
                    throw TomlError.duplicateKey(String(describing: keyPath))
                }
                for depth in 1...keyPath.count where inlineTables.contains(Path(Array(keyPath.prefix(depth)))) {
                    throw TomlError.duplicateKey(String(describing: keyPath))
                }

                // Nor may a table be opened underneath a key that holds a
                // value: `a = 1` leaves nowhere for `[a.b]` to go. An array
                // of tables is the exception -- `[[a]]` then `[a.b]` adds a
                // sub-table to its most recent element.
                for depth in 1..<keyPath.count {
                    let prefix = Array(keyPath.prefix(depth))
                    if toml.hasKey(key: prefix, includeTables: false),
                       !tableArrays.contains(Path(prefix)) {
                        throw TomlError.duplicateKey(String(describing: prefix))
                    }
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
                sawIdentifier = false
            } else if case .Identifier(let val) = subToken {
                guard !sawIdentifier else {
                    throw TomlError.syntaxError("Table name parts must be separated by '.'")
                }
                emptyTableSep = false
                sawIdentifier = true
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
        // As in `setTable`: two names in a row mean a separator is missing.
        var sawIdentifier = false

        tableLoop: while let subToken = tokens.popFirst() {
            if case .TableArrayEnd = subToken {
                if keyPath.isEmpty {
                    throw TomlError.syntaxError("Table array name must not be blank")
                }

                let tableTokens = try getTableTokens(keyPath: keyPath, tokens: &tokens)

                var tableParser = Parser()
                try tableParser.parse(tokens: tableTokens)

                let path = Path(keyPath)

                // `[[albums.songs]]` makes `albums` a table, and a table is
                // not an array of tables: a later `[[albums]]` has nothing to
                // append to.
                if implicitTables.contains(path), !tableArrays.contains(path) {
                    throw TomlError.duplicateKey(String(describing: keyPath))
                }
                for depth in 1..<keyPath.count {
                    implicitTables.insert(Path(Array(keyPath.prefix(depth))))
                }

                if toml.hasKey(key: keyPath) {
                    // Only an array that previous `[[...]]` headers built may
                    // be appended to. `fruit = []` followed by `[[fruit]]` is
                    // an error, though an empty `[Any]` casts to `[Toml]`
                    // happily enough to hide it.
                    guard tableArrays.contains(path), var arr: [Toml] = toml.array(keyPath) else {
                        throw TomlError.duplicateKey(String(describing: keyPath))
                    }
                    arr.append(tableParser.toml)
                    toml.set(value: arr, for: keyPath)
                } else {
                    toml.set(value: [tableParser.toml], for: keyPath)
                }
                tableArrays.insert(path)
                sawEnd = true
                break tableLoop
            } else if case .TableSep = subToken {
                sawIdentifier = false
            } else if case .Identifier(let val) = subToken {
                guard !sawIdentifier else {
                    throw TomlError.syntaxError("Table name parts must be separated by '.'")
                }
                sawIdentifier = true
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

        // An inline table defines its key outright, so the key must be free:
        // `a.b = 0` followed by `a = {}` replaces a table that already
        // exists, which is not allowed.
        if toml.hasKey(key: keyPath) {
            throw TomlError.duplicateKey(String(describing: keyPath))
        }

        let tableTokens = extractTableTokens(tokens: &tokens, inline: true)
        try parse(tokens: try inlineTableEntryTokens(tableTokens))

        toml.setTable(key: keyPath)
        inlineTables.insert(Path(keyPath))

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

        checkAndSetArray(check: arr, key: myKeyPath, out: &toml)
    }
}
