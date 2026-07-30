# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

- **Build**: `swift build`
- **Run all tests**: `swift test`
- **Run specific test**: `swift test --filter TestName`
- **Conformance suite**: `Scripts/toml-test.sh` (TOML 1.1.0) and `Scripts/toml-test.sh 1.0.0`; needs Go, which builds the runner
- **Swift Version**: 6.3+ (v6 language mode enabled), minimum platform macOS/iOS 26
- **TOML Version**: 1.1.0

## Architecture Overview

This is a Swift TOML parser library following a clean lexer-parser architecture:

1. **Lexing Phase** (`Lexer.swift`): Converts raw TOML string into tokens using regex-based evaluators defined in `Grammar.swift`
2. **Parsing Phase** (`Parser.swift`): Transforms token stream into internal data structures
3. **Public API** (`Toml.swift`): Provides type-safe accessors and serialization

The parsing flow: Input String → Lexer → Tokens → Parser → Toml Object

`Sources/TomlTestDecoder` is a small executable that reads TOML on stdin and
writes toml-test's tagged JSON on stdout. It exists only for the conformance
suite; nothing in the library depends on it.

## Key Implementation Details

- **Error Handling**: Uses `TomlError` enum with descriptive cases. Parser throws on errors, accessors return optionals
- **Grammar System**: Evaluators in `Grammar.swift` define TOML syntax rules using closures that consume input and produce tokens. Each evaluator may push and pop lexer states; the state left on the stack decides what may come next, which is how `eol` makes `a = 1 b = 2` an error
- **Value Access**: Type-safe accessors (string, int, double, bool, date, array) with optional returns
- **Local date/time**: Stored as `TomlDate`, not `String`, so that a bare `1979-05-27` is not confused with a quoted one and serializes back out unquoted
- **Definedness**: `Parser` tracks how each path was defined (`declaredTables`, `dottedKeyTables`, `inlineTables`, `tableArrays`, `implicitTables`) to reject redefinition -- an inline table is closed for good, a table a header defined cannot be reopened by a dotted key, and so on
- **Path System**: Uses dot-notation for nested key access (e.g., "server.ip")

## Testing Approach

Tests use Swift Testing framework (migrated from XCTest) with actual TOML files as fixtures in `Tests/TomlTests/`. Each test file tests specific TOML features:
- Basic types: `bool_*.toml`, `int_*.toml`, `float_*.toml`, `string_*.toml`
- Complex structures: `array_*.toml`, `table_*.toml`, `inline_table_*.toml`
- Edge cases: `hard_example.toml`, `duplicate_*.toml`
- Error cases: Tests that verify proper error handling for malformed TOML

Test functions use `@Test("descriptive name")` annotations and `#expect()` assertions for validation and `#expect(throws:)` for error testing.

`Spec11Tests.swift` covers the TOML 1.1.0 syntax and the specification
conformance rules; `RegressionTests.swift` covers previously fixed bugs. The
exhaustive check is the toml-test suite, run by `Scripts/toml-test.sh` and in
CI -- prefer adding a case there in spirit (a small `withString:` test) over
relying on the suite alone, so that a failure names what broke.

## Known Issues

- None currently; `swift test` and both toml-test runs pass in full.
- The library is a decoder as far as toml-test is concerned; `Serialize.swift`
  writes TOML back out, but the encoder half of the suite is not wired up.