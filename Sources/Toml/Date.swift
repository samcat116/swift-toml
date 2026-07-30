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

private let rfc3339formatter =
    SharedDateFormatter(format: "yyyy'-'MM'-'dd'T'HH':'mm':'ssZZZZZ")

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

    // rfc3339 w fractional seconds w/ time offset
    init?(rfc3339String: String, fractionalSeconds: Bool = true, localTime: Bool = false) {
        var dateStr = rfc3339String

        if localTime {
            dateStr += localTimeOffset()
        }

        let dateFormatter = fractionalSeconds ? rfc3339fractionalformatter : rfc3339formatter

        guard let d = dateFormatter.formatter.date(from: dateStr) else {
            return nil
        }
        self.init(timeInterval: 0, since: d)
    }

    func rfc3339String() -> String {
        return rfc3339fractionalformatter.formatter.string(from: self)
    }

}
