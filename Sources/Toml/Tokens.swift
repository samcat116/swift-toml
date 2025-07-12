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

enum Token: Hashable {
    case Identifier(String)
    case Key(String)
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

    func hash(into hasher: inout Hasher) {
        hasher.combine(caseHashValue)
    }

    private var caseHashValue: Int {
        switch self {
        case .Identifier:
            return 0
        case .Key:
            return 1
        case .IntegerNumber:
            return 2
        case .DoubleNumber:
            return 3
        case .Boolean:
            return 4
        case .DateTime:
            return 5
        case .LocalDate:
            return 6
        case .LocalTime:
            return 7
        case .LocalDateTime:
            return 8
        case .ArrayBegin:
            return 9
        case .ArrayEnd:
            return 10
        case .TableArrayBegin:
            return 11
        case .TableArrayEnd:
            return 12
        case .InlineTableBegin:
            return 13
        case .InlineTableEnd:
            return 14
        case .TableBegin:
            return 15
        case .TableSep:
            return 16
        case .TableEnd:
            return 17
        case .Comment:
            return 18
        }
    }

    var value : Any? {
        switch self {
        case .Identifier(let val):
            return val
        case .Key(let val):
            return val
        case .IntegerNumber(let val):
            return val
        case .DoubleNumber(let val):
            return val
        case .Boolean(let val):
            return val
        case .DateTime(let val):
            return val
        case .LocalDate(let val):
            return val
        case .LocalTime(let val):
            return val
        case .LocalDateTime(let val):
            return val
        case .Comment(let val):
            return val
        default:
            return nil
        }
    }
    
    static func == (lhs: Token, rhs: Token) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }
    
}

typealias TokenGenerator = (String) throws -> Token?
