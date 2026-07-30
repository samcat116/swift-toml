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

func getUnicodeChar(unicode: String) throws(TomlError) -> String {
    // A `\u` escape must be exactly four hex digits and a `\U` escape exactly
    // eight; the caller guarantees the count, this validates the digits.
    guard let code = UInt32(unicode, radix: 16) else {
        throw TomlError.invalidEscapeSequence("\\u" + unicode)
    }

    // Scalar values in the surrogate range and above U+10FFFF do not exist.
    guard let scalar = Unicode.Scalar(code) else {
        throw TomlError.invalidUnicodeCharacter(Int(code))
    }

    return String(scalar)
}

/// Name the escape a partially-read run of hex digits belongs to, for error
/// reporting: `\x` takes two digits, `\u` four and `\U` eight.
private func escapePrefix(remaining: Int, digits: String) -> String {
    switch remaining + digits.count {
    case 2: return "\\x"
    case 8: return "\\U"
    default: return "\\u"
    }
}

func checkEscape(char: Character, escape: inout Bool) throws(TomlError) -> (String, Int) {
    var unicodeSize = -1
    var s: String = ""

    switch char {
        case "n":
            s = "\n"
            escape = false
        case "\\":
            s = "\\"
            escape = false
        case "\"":
            s = "\""
            escape = false
        case "f":
            s = "\u{000C}"
            escape = false
        case "b":
            s = "\u{0008}"
            escape = false
        case "t":
            s = "\t"
            escape = false
        case "r":
            s = "\r"
            escape = false
        case "e":
            s = "\u{001B}"  // ESC character (ASCII 27)
            escape = false
        case "x":
            // TOML 1.1.0: two hex digits, for code points up to U+00FF.
            unicodeSize = 2
        case "u":
            unicodeSize = 4
        case "U":
            unicodeSize = 8
        default:
            throw TomlError.invalidEscapeSequence("\\" + String(char))
    }

    return (s, unicodeSize)
}

extension String {
    func trim() -> String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /**
        The content of a multi-line string, as the spec defines it.

        Two things happen to the text between the delimiters: CRLF line
        endings are normalized to LF, and a newline immediately following the
        opening delimiter is dropped. Everything else -- including trailing
        whitespace before the closing delimiter -- is part of the string.

        This used to be a `trim()`, which additionally ate leading and
        trailing whitespace that the document asked for.
    */
    func multilineStringContent() -> String {
        var content = contains("\r\n") ? replacingOccurrences(of: "\r\n", with: "\n") : self
        if content.hasPrefix("\n") {
            content.removeFirst()
        }
        return content
    }

    func stripLineContinuation() -> String {
        // A backslash at the end of a line in a multi-line string discards
        // the backslash and all following whitespace.
        //
        // Escaped backslashes are consumed in pairs first, so the second
        // backslash of a `\\` immediately before a newline is not mistaken
        // for a line continuation. The previous implementation matched with a
        // regex and then called `replacingOccurrences` for each match, which
        // rewrote the whole string once per match and stripped every other
        // copy of the matched text along with it.
        var result = ""
        result.reserveCapacity(count)

        var rest = self[...]
        while let backslash = rest.firstIndex(of: "\\") {
            result.append(contentsOf: rest[..<backslash])

            let afterBackslash = rest.index(after: backslash)
            guard afterBackslash < rest.endIndex else {
                result.append("\\")
                return result
            }

            let next = rest[afterBackslash]
            if next == "\\" {
                // Escaped backslash: keep both, and do not let the second one
                // start a continuation.
                result.append("\\\\")
                rest = rest[rest.index(after: afterBackslash)...]
            } else if next.isWhitespace {
                var scan = afterBackslash
                var reachedNewline = false
                while scan < rest.endIndex, rest[scan].isWhitespace {
                    reachedNewline = reachedNewline || rest[scan].isNewline
                    scan = rest.index(after: scan)
                }

                if reachedNewline {
                    // Line continuation: drop the backslash and the run of
                    // whitespace that follows it.
                    rest = rest[scan...]
                } else {
                    // Only whitespace that runs to the end of the line makes
                    // a continuation. A backslash followed by a space in the
                    // middle of a line is an invalid escape, which the escape
                    // pass reports once the backslash is left in place.
                    result.append("\\")
                    rest = rest[afterBackslash...]
                }
            } else {
                result.append("\\")
                rest = rest[afterBackslash...]
            }
        }

        result.append(contentsOf: rest)
        return result
    }

    func replaceEscapeSequences() throws(TomlError) -> String {
        var s = "" // new string that is being constructed
        s.reserveCapacity(count)
        var escape = false
        var unicode = ""
        var unicodeSize = -1

        for char in self {
            if escape {
                if unicodeSize == 0 {
                    s += try getUnicodeChar(unicode: unicode)
                    escape = false
                    unicodeSize = -1
                    unicode = ""
                    // Don't add the current char - we just finished processing a unicode sequence
                    // Now process this char normally
                    if char == "\\" {
                        escape = true
                    } else {
                        s.append(char)
                    }
                } else if unicodeSize > 0 {
                    unicodeSize -= 1
                    unicode.append(char)
                } else {
                    let (newChar, size) = try checkEscape(char: char, escape: &escape)
                    s += newChar
                    unicodeSize = size
                }
            } else if char == "\\" {
                escape = true
            } else {
                s.append(char)
            }
        }

        if unicodeSize == 0 {
            s += try getUnicodeChar(unicode: unicode)
        } else if escape {
            // The string ended part-way through an escape sequence. This used
            // to fall off the end silently, discarding the incomplete escape
            // and everything the caller expected with it: `a = "\u00"` parsed
            // to the empty string instead of reporting an error.
            throw TomlError.invalidEscapeSequence(
                unicodeSize > 0 ? escapePrefix(remaining: unicodeSize, digits: unicode) + unicode : "\\")
        }

        return s
    }
}

// Mark: String related array extensions

/**
    Does this scalar force a key to be quoted when serialized?

    Bare keys are `[A-Za-z0-9_-]`; everything else needs quoting. Spelled out
    as the complement of that set to match the ranges the serializer has
    always used.
*/
private func requiresQuoting(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x20...0x2B,   // space through +
         0x2E...0x2F,   // . /
         0x3A...0x40,   // : through @
         0x5B...0x5E,   // [ through ^
         0x60:          // `
        return true
    default:
        // Everything from { upward, including scalars outside the BMP.
        return scalar.value >= 0x7B
    }
}

func quoted(_ value: String) -> String {
    // A direct scalar scan. The previous implementation ran a
    // `.*[ranges]+.*` regex per key, which made the engine backtrack across
    // the whole key on every miss, and could not see past a newline because
    // `.` does not match line separators.
    value.unicodeScalars.contains(where: requiresQuoting) ? "\"\(value)\"" : value
}

/**
    Escape the string according to the rules of a single line Toml string

    - Parameter string: The string to escape

    - Returns: Escaped version of the string
*/
func escape(string: String) -> String {
    // Built in one pass. The previous implementation ran
    // `replacingOccurrences` once per escape mapping, walking the string six
    // times and reallocating on each pass.
    var result = ""
    result.reserveCapacity(string.count)

    for char in string {
        switch char {
        case "\\": result += "\\\\"
        case "\n": result += "\\n"
        case "\r": result += "\\r"
        case "\t": result += "\\t"
        case "\"": result += "\\\""
        case "\u{001B}": result += "\\e"
        default: result.append(char)
        }
    }

    return result
}
