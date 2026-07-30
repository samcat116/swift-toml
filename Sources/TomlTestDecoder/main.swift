/*
 * A decoder for the toml-test conformance suite
 * (https://github.com/toml-lang/toml-test).
 *
 * Reads a TOML document on stdin and writes toml-test's tagged JSON encoding
 * of it to stdout. A document that fails to parse exits non-zero with the
 * error on stderr, which is how the suite's invalid cases are checked.
 */

import Foundation
import Toml

/// toml-test writes every scalar as `{"type": ..., "value": ...}`, with
/// tables as JSON objects and arrays as JSON arrays.
private func tagged(_ type: String, _ value: String) -> [String: String] {
    ["type": type, "value": value]
}

private func encode(value: Any) -> Any {
    switch value {
    case let bool as Bool:
        return tagged("bool", bool ? "true" : "false")
    case let int as Int:
        return tagged("integer", String(int))
    case let double as Double:
        // Swift's description is the shortest form that round-trips, and
        // spells the specials the way TOML does.
        return tagged("float", String(double))
    case let string as String:
        return tagged("string", string)
    case let date as Date:
        return tagged("datetime", utcFormatter.string(from: date))
    case let local as TomlDate:
        switch local.kind {
        case .localDate: return tagged("date-local", local.text)
        case .localTime: return tagged("time-local", local.text)
        case .localDateTime: return tagged("datetime-local", local.text)
        }
    case let table as Toml:
        return encode(toml: table)
    case let array as [Any]:
        return array.map(encode(value:))
    default:
        // The typed array cases: `[Int]`, `[String]` and friends do not cast
        // to `[Any]` without being rebuilt element by element.
        return encodeTypedArray(value) ?? tagged("string", String(describing: value))
    }
}

private func encodeTypedArray(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .collection else {
        return nil
    }
    return mirror.children.map { encode(value: $0.value) }
}

/// Insert `value` into the nested object `object` at `path`, creating any
/// intermediate objects.
private func insert(_ value: Any, at path: [String], into object: inout [String: Any]) {
    guard let head = path.first else {
        return
    }

    if path.count == 1 {
        object[head] = value
        return
    }

    var child = object[head] as? [String: Any] ?? [:]
    insert(value, at: Array(path.dropFirst()), into: &child)
    object[head] = child
}

private func encode(toml: Toml) -> [String: Any] {
    var root = [String: Any]()

    // Tables first, shallowest first, so that a table with no keys of its own
    // still shows up as an empty object.
    for table in toml.tableNames.sorted(by: { $0.components.count < $1.components.count }) {
        var cursor = root
        insertTableIfMissing(table.components, into: &cursor)
        root = cursor
    }

    for key in toml.keyNames {
        guard let value: Any = toml.value(key.components) else {
            continue
        }
        insert(encode(value: value), at: key.components, into: &root)
    }

    return root
}

private func insertTableIfMissing(_ path: [String], into object: inout [String: Any]) {
    guard let head = path.first else {
        return
    }

    var child = object[head] as? [String: Any] ?? [:]
    if path.count > 1 {
        insertTableIfMissing(Array(path.dropFirst()), into: &child)
    }
    object[head] = child
}

private let utcFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss.SSSSSS'Z'"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.calendar = Calendar(identifier: .iso8601)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

// Decoding must fail rather than substitute replacement characters: a TOML
// document is UTF-8 by definition, so invalid bytes make it invalid TOML.
guard let input = String(data: FileHandle.standardInput.readDataToEndOfFile(),
                         encoding: .utf8) else {
    FileHandle.standardError.write(Data("input is not valid UTF-8\n".utf8))
    exit(1)
}

do {
    let toml = try Toml(withString: input)
    let json = try JSONSerialization.data(withJSONObject: encode(toml: toml),
                                          options: [.sortedKeys])
    FileHandle.standardOutput.write(json)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
