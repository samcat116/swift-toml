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

/**
    A TOML local date, local time, or local date-time.

    These are wall-clock values with no time zone, so no `Date` can hold one
    without inventing an offset for it. They were previously stored as plain
    `String`s, which lost the distinction between `d = 1979-05-27` and
    `d = "1979-05-27"` -- the former then serialized back out quoted, as a
    string.
*/
public struct TomlDate: Hashable, Sendable, CustomStringConvertible {
    public enum Kind: Sendable, Hashable {
        case localDate
        case localTime
        case localDateTime
    }

    public let kind: Kind
    /// The value exactly as it was written in the document.
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }

    public var description: String { text }
}

private func buildDateFormatter(format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = format
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.calendar = Calendar(identifier: .iso8601)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}

/**
    Holds a fully configured `DateFormatter` for sharing.

    `DateFormatter` is documented as safe to use from several threads at once
    provided it is not mutated after configuration, which holds here: these are
    configured by `buildDateFormatter` and thereafter only read. The wrapper
    states that explicitly rather than depending on whether a given platform's
    Foundation happens to declare `DateFormatter` as `Sendable` -- Darwin does,
    swift-corelibs-foundation has not always.

    `Date.ISO8601FormatStyle` would avoid the shared reference type, but it can
    only emit three fractional-second digits. These formats emit six, and that
    is the library's serialized output -- changing it would silently alter
    every document consumers round-trip.
*/
private struct SharedDateFormatter: @unchecked Sendable {
    let formatter: DateFormatter

    init(format: String) {
        formatter = buildDateFormatter(format: format)
    }
}

private let rfc3339fractionalformatter =
    SharedDateFormatter(format: "yyyy'-'MM'-'dd'T'HH':'mm':'ss.SSSSSSZZZZZ")

private func isLeapYear(_ year: Int) -> Bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

private func daysInMonth(year: Int, month: Int) -> Int {
    switch month {
    case 1, 3, 5, 7, 8, 10, 12: return 31
    case 4, 6, 9, 11: return 30
    case 2: return isLeapYear(year) ? 29 : 28
    default: return 0
    }
}

/**
    Check the component ranges of a TOML date and/or time.

    The lexer's patterns fix the shape -- two digits here, a colon there -- but
    say nothing about the values, so without this `2023-02-30T25:61:00` is
    well-formed. `DateFormatter` is no help either: it rolls such a date over
    into the following month rather than rejecting it.

    - Parameter text: A local date, local time, local date-time or offset
                      date-time, in the shape the lexer matched
*/
func hasValidDateTimeComponents(_ text: String) -> Bool {
    var rest = Substring(text)

    // Leading date, if this is not a time on its own.
    if rest.count >= 10, rest[rest.index(rest.startIndex, offsetBy: 4)] == "-" {
        let fields = rest.prefix(10).split(separator: "-")
        guard fields.count == 3,
              let year = Int(fields[0]),
              let month = Int(fields[1]),
              let day = Int(fields[2]),
              (1...12).contains(month),
              (1...daysInMonth(year: year, month: month)).contains(day) else {
            return false
        }

        rest = rest.dropFirst(10)
        guard !rest.isEmpty else {
            return true
        }
        rest = rest.dropFirst()  // the T/t/space separator
    }

    // Trailing offset, if any.
    if let last = rest.last, last == "Z" || last == "z" {
        rest = rest.dropLast()
    } else if rest.count >= 6 {
        let signIndex = rest.index(rest.endIndex, offsetBy: -6)
        if rest[signIndex] == "+" || rest[signIndex] == "-" {
            let fields = rest[rest.index(after: signIndex)...].split(separator: ":")
            guard fields.count == 2,
                  let hour = Int(fields[0]), let minute = Int(fields[1]),
                  hour <= 23, minute <= 59 else {
                return false
            }
            rest = rest[..<signIndex]
        }
    }

    guard !rest.isEmpty else {
        return true
    }

    var timeText = rest
    if let dot = timeText.firstIndex(of: ".") {
        timeText = timeText[..<dot]
    }

    let fields = timeText.split(separator: ":")
    guard (2...3).contains(fields.count),
          let hour = Int(fields[0]), let minute = Int(fields[1]),
          hour <= 23, minute <= 59 else {
        return false
    }

    if fields.count == 3 {
        // 60 is a leap second, which RFC 3339 allows.
        guard let second = Int(fields[2]), second <= 60 else {
            return false
        }
    }

    return true
}

/**
    Return the text of a date-time, having checked its component ranges.

    - Throws: `TomlError.invalidDateFormat` if a component is out of range
*/
func validatedDateTime(_ matched: Substring) throws(TomlError) -> String {
    let text = String(matched)
    guard hasValidDateTimeComponents(text) else {
        throw TomlError.invalidDateFormat(text)
    }
    return text
}

/**
    Rewrite the date/time separator as the `T` that RFC 3339 and the rest of
    this library use.

    TOML also accepts a lower case `t` and, for readability, a single space.

    - Parameter input: Text whose first ten characters are `yyyy-MM-dd`
*/
func normalizedDateTimeSeparator(_ input: Substring) -> String {
    var text = String(input)
    guard text.count > 10 else {
        return text
    }
    let separator = text.index(text.startIndex, offsetBy: 10)
    if text[separator] != "T" {
        text.replaceSubrange(separator...separator, with: "T")
    }
    return text
}

/**
    Rewrite a TOML date-time into the single fixed shape the formatter reads:
    `T` separator, explicit seconds, exactly six fractional digits.

    TOML admits more spellings than any one `DateFormatter` format string can:
    the separator may be `T`, `t` or a space; seconds are optional as of
    1.1.0; and fractional seconds may have any number of digits, of which the
    spec allows a parser to keep as many as it can represent.

    - Returns: The normalized text, or `nil` if the input is not a date-time
*/
private func normalizedRFC3339(_ input: String) -> String? {
    var chars = Array(input)
    // The shortest form this accepts is `yyyy-MM-ddTHH:mm`.
    guard chars.count >= 16 else {
        return nil
    }

    var offset = ""
    if let last = chars.last, last == "Z" || last == "z" {
        offset = "Z"
        chars.removeLast()
    } else if chars.count >= 6 {
        let signIndex = chars.count - 6
        if chars[signIndex] == "+" || chars[signIndex] == "-" {
            offset = String(chars[signIndex...])
            chars.removeSubrange(signIndex...)
        }
    }

    guard chars.count > 11 else {
        return nil
    }

    var time = String(chars[11...])
    var fraction = ""
    if let dot = time.firstIndex(of: ".") {
        fraction = String(time[time.index(after: dot)...])
        time = String(time[..<dot])
    }

    if time.count == 5 {
        // Seconds omitted (TOML 1.1.0).
        time += ":00"
    }
    guard time.count == 8 else {
        return nil
    }

    // Microsecond resolution: anything finer is truncated, which the spec
    // permits, and anything coarser is zero-padded to satisfy the format.
    fraction = String((fraction + "000000").prefix(6))

    return String(chars[0..<10]) + "T" + time + "." + fraction + offset
}

/**
    The current time zone's UTC offset, formatted as RFC 3339 requires.

    The previous implementation built this with
    `String(format: "%02d%02d", hours, minutes)`, which had three defects: the
    mandatory `+`/`-` sign was missing, the `:` separator was missing, and
    negative offsets rendered a stray sign on the minutes with no zero
    padding, so `-05:30` came out as `-5-30`.
*/
private func localTimeOffset() -> String {
    let totalSeconds = TimeZone.current.secondsFromGMT()
    let sign = totalSeconds < 0 ? "-" : "+"
    let magnitude = abs(totalSeconds)
    // The sign is concatenated rather than passed as a `%@` argument: `String`
    // is not a `CVarArg` on all platforms' Foundation.
    return sign + String(format: "%02d:%02d", magnitude / 3600, (magnitude % 3600) / 60)
 }

extension Date {

    /**
        Parse an RFC 3339 date-time in any of the spellings TOML allows.

        - Parameter rfc3339String: The date-time text
        - Parameter localTime: Interpret an offset-less date-time as being in
                               the current time zone
    */
    init?(rfc3339String: String, localTime: Bool = false) {
        guard var dateStr = normalizedRFC3339(rfc3339String) else {
            return nil
        }

        if localTime {
            dateStr += localTimeOffset()
        }

        guard let d = rfc3339fractionalformatter.formatter.date(from: dateStr) else {
            return nil
        }
        self.init(timeInterval: 0, since: d)
    }

    func rfc3339String() -> String {
        return rfc3339fractionalformatter.formatter.string(from: self)
    }

}
