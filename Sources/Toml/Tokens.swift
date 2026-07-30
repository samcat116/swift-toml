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
    The kind of a `Token`, ignoring any associated value.

    `Token` deliberately hashes and compares by kind alone so that the
    parser's dispatch table can be keyed by kind. Spelling that out as its own
    type keeps the intent explicit; the previous implementation compared
    `hashValue`s, which made equality depend on hashing and silently breaks if
    a case ever contributes its payload to the hash.
*/
enum TokenKind: Hashable, Sendable {
    case identifier
    case key
    case integerNumber
    case doubleNumber
    case boolean
    case dateTime
    case localDate
    case localTime
    case localDateTime
    case arrayBegin
    case arrayEnd
    case tableArrayBegin
    case tableArrayEnd
    case inlineTableBegin
    case inlineTableEnd
    case tableBegin
    case tableSep
    case tableEnd
    case comment
    case comma
}

enum Token: Hashable, Sendable {
    case Identifier(String)
    /// A key declaration, already split into its dotted components.
    case Key([String])
    case IntegerNumber(Int)
    case DoubleNumber(Double)
    case Boolean(Bool)
    case DateTime(Date)
    case LocalDate(String)      // Local date: 1979-05-27
    case LocalTime(String)      // Local time: 07:32:00
    case LocalDateTime(String)  // Local date-time: 1979-05-27T07:32:00
    case ArrayBegin
    case ArrayEnd
    case TableArrayBegin
    case TableArrayEnd
    case InlineTableBegin
    case InlineTableEnd
    case TableBegin
    case TableSep
    case TableEnd
    case Comment(String)
    /// The separator between array elements or inline table entries.
    case Comma

    var kind: TokenKind {
        switch self {
        case .Identifier: .identifier
        case .Key: .key
        case .IntegerNumber: .integerNumber
        case .DoubleNumber: .doubleNumber
        case .Boolean: .boolean
        case .DateTime: .dateTime
        case .LocalDate: .localDate
        case .LocalTime: .localTime
        case .LocalDateTime: .localDateTime
        case .ArrayBegin: .arrayBegin
        case .ArrayEnd: .arrayEnd
        case .TableArrayBegin: .tableArrayBegin
        case .TableArrayEnd: .tableArrayEnd
        case .InlineTableBegin: .inlineTableBegin
        case .InlineTableEnd: .inlineTableEnd
        case .TableBegin: .tableBegin
        case .TableSep: .tableSep
        case .TableEnd: .tableEnd
        case .Comment: .comment
        case .Comma: .comma
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
    }

    var value: Any? {
        switch self {
        case .Identifier(let val): val
        case .Key(let val): val
        case .IntegerNumber(let val): val
        case .DoubleNumber(let val): val
        case .Boolean(let val): val
        case .DateTime(let val): val
        case .LocalDate(let val): TomlDate(kind: .localDate, text: val)
        case .LocalTime(let val): TomlDate(kind: .localTime, text: val)
        case .LocalDateTime(let val): TomlDate(kind: .localDateTime, text: val)
        case .Comment(let val): val
        default: nil
        }
    }

    static func == (lhs: Token, rhs: Token) -> Bool {
        lhs.kind == rhs.kind
    }
}

typealias TokenGenerator = @Sendable (Substring) throws(TomlError) -> Token?
