# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

- **Build**: `swift build`
- **Run all tests**: `swift test`
- **Run specific test**: `swift test --filter TestName`
- **Swift Version**: 6.0+ (language mode enabled)

## Architecture Overview

This is a Swift TOML parser library following a clean lexer-parser architecture:

1. **Lexing Phase** (`Lexer.swift`): Converts raw TOML string into tokens using regex-based evaluators defined in `Grammar.swift`
2. **Parsing Phase** (`Parser.swift`): Transforms token stream into internal data structures
3. **Public API** (`Toml.swift`): Provides type-safe accessors and serialization

The parsing flow: Input String → Lexer → Tokens → Parser → Toml Object

## Key Implementation Details

- **Error Handling**: Uses `TomlError` enum with descriptive cases. Parser throws on errors, accessors return optionals
- **Grammar System**: Evaluators in `Grammar.swift` define TOML syntax rules using closures that consume input and produce tokens
- **Value Access**: Type-safe accessors (string, int, double, bool, date, array) with optional returns
- **Path System**: Uses dot-notation for nested key access (e.g., "server.ip")

## Testing Approach

Tests use Swift Testing framework (migrated from XCTest) with actual TOML files as fixtures in `Tests/TomlTests/`. Each test file tests specific TOML features:
- Basic types: `bool_*.toml`, `int_*.toml`, `float_*.toml`, `string_*.toml`
- Complex structures: `array_*.toml`, `table_*.toml`, `inline_table_*.toml`
- Edge cases: `hard_example.toml`, `duplicate_*.toml`
- Error cases: Tests that verify proper error handling for malformed TOML

Test functions use `@Test("descriptive name")` annotations and `#expect()` assertions for validation and `#expect(throws:)` for error testing.

## Known Issues

- One failing test related to floating-point precision in serialization
- This doesn't affect core parsing functionality