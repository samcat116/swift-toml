[![Build Status](https://travis-ci.org/jdfergason/swift-toml.svg?branch=master)](https://travis-ci.org/jdfergason/swift-toml)
[![codebeat badge](https://codebeat.co/badges/21ffbe72-dd12-4d9d-ad01-cfdf423ea5fa)](https://codebeat.co/projects/github-com-jdfergason-swift-toml)

# SwiftToml

SwiftToml is a TOML parser written in the swift language.  TOML is an intuitive
configuration file format that is designed to be easy for humans to read and
computers to parse.

SwiftToml parses files that conform to **version 1.1.0** of the TOML spec, and
passes the whole [toml-test](https://github.com/toml-lang/toml-test) suite for
it: 189 valid documents and 362 invalid ones.

For full details of writing TOML files see the [TOML documentation](https://github.com/toml-lang/toml).

# Quickstart

TOML files are parsed using one of two functions:

1. Read TOML from file
2. Parse TOML from string

Both functions return a Toml object of parsed key/value pairs

## Parse TOML from file on disk

```swift
import Toml
let toml = try Toml(contentsOfFile: "/path/to/file.toml")
```

## Parse TOML from string

```swift
import Toml
let toml = try Toml(withString: "answer = 42")
```

## Get raw values from TOML document

```swift
import Toml
let toml = try Toml(contentsOfFile: "/path/to/file.toml")

// string value
print(toml.string("table1", "name"))

// boolean value
print(toml.bool("table1", "manager"))

// integer value
print(toml.int("table1", "age"))

// double value
print(toml.double("table1", "rating"))

// date value
print(toml.date("table1", "birthday"))

// get value and resolve type at runtime
print(try toml.value("title")!)

// get array of type [String]
let array: [String] = toml.array("locations")!

// get table
let table1 = toml.table("table1")

// iterate over all tables at the root level
for (tablePath, table) in toml.tables() { ... }

// iterate over all tables under table1
for (tablePath, table) in toml.tables("table1") { ... }

// access local date/time values
let localDate = toml.localDate("birthday")      // "1979-05-27"
let localTime = toml.localTime("start_time")    // "07:32:00"
let localDateTime = toml.localDateTime("created") // "1979-05-27T07:32:00"

// ... or as a value that knows which of the three it is
let birthday = toml.tomlDate("birthday")        // TomlDate(kind: .localDate, text: "1979-05-27")

// dotted keys access nested values directly
let config = toml.string("database", "host")    // equivalent to [database] host = "..."
let port = toml.int("server", "port")           // equivalent to [server] port = 8080
```

## Installation

Add the project to  to your Package.swift file as a dependency:

    dependencies: [
        .Package(url: "http://github.com/jdfergason/swift-toml", majorVersion: 1)
    ]

## Compatibility

SwiftToml is compatible with Swift 6.3+ and TOML 1.1.0, and requires
macOS 26 / iOS 26 / tvOS 26 / watchOS 26 or later.

Errors are reported through `TomlError`, whose cases use lowerCamelCase
(`TomlError.syntaxError`, `TomlError.duplicateKey`, and so on). `init(withString:)`
declares `throws(TomlError)`, so a `catch` binds the concrete error type
without a cast.

### TOML 1.1.0 features

- **Multi-line inline tables**: newlines, comments and a trailing comma inside `{ ... }`
- **Hex escapes**: `\x41` for code points up to U+00FF
- **Escape character**: `\e`
- **Optional seconds**: `14:15` and `2010-02-03 14:15` as well as `14:15:00`

### TOML 1.0.0 features

- **Integer formats**: Hexadecimal (`0xDEAD`), octal (`0o755`), binary (`0b1010`)
- **Number separators**: Underscores in numbers (`1_000_000`, `3.141_592`)
- **Special float values**: Infinity (`inf`, `-inf`) and NaN (`nan`)
- **Date and time types**: Local dates (`1979-05-27`), local times (`07:32:00`), local date-times (`1979-05-27T07:32:00`)
- **Dotted keys**: Nested key syntax (`site.owner.name = "value"`), including quoted parts (`a."b.c".d`)
- **Offset date-times**: RFC 3339 timestamps, with `T`, `t` or a space before the time
- **Mixed-type arrays**: `[ 0.1, 1, "two" ]`

## Tests

To run the unit tests checkout the repository and type:

    swift test

To run the [toml-test](https://github.com/toml-lang/toml-test) conformance
suite, which checks the parser against every document the specification has an
opinion about:

    Scripts/toml-test.sh          # TOML 1.1.0
    Scripts/toml-test.sh 1.0.0    # TOML 1.0.0

Both pass in full. The 1.0.0 run skips the nine documents that 1.1.0 made
legal — a 1.1.0 parser is supposed to accept those, and the 1.0.0 suite lists
them as documents to reject. The suite needs Go, which is used only to build
its runner; `Sources/TomlTestDecoder` is the adapter it drives.

## License

[Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0.txt)
