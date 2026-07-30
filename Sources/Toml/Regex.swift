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

/**
    A compiled pattern that matches only at the start of the input it is
    given.

    The grammar's patterns are written against UTF-16 code unit ranges (for
    example `[ -￿]`), so matching uses unicode scalar semantics
    rather than the default grapheme cluster semantics. Under grapheme
    semantics a single `Character` such as an emoji with a variation selector
    would have to match a character class as a unit, which those scalar
    ranges are not written to express.
*/
/// - Note: `@unchecked` because `Regex<AnyRegexOutput>` carries no `Sendable`
///   conformance (`AnyRegexOutput` is not `Sendable`). The value is immutable
///   after `init` and is only ever read, and matching a shared `Regex`
///   concurrently — including the first match, which lowers the pattern
///   lazily — is clean under ThreadSanitizer.
struct Pattern: @unchecked Sendable {
    private let regex: Regex<AnyRegexOutput>

    /**
        Compile `pattern`.

        The patterns are compile-time constants owned by `Grammar`, so an
        invalid one is a programming error rather than a malformed-input
        condition and traps rather than throwing.

        - Parameter pattern: An ICU-style regular expression
        - Parameter dotMatchesNewlines: Allow `.` to match line separators
    */
    init(_ pattern: String, dotMatchesNewlines: Bool = false) {
        guard let compiled = try? Regex(pattern) else {
            preconditionFailure("invalid TOML grammar pattern: \(pattern)")
        }
        self.regex = compiled
            .matchingSemantics(.unicodeScalar)
            .dotMatchesNewlines(dotMatchesNewlines)
    }

    /**
        Match this pattern against the start of `input`.

        - Parameter input: The text to match against

        - Returns: The matched slice of `input`, or `nil` if the pattern does
                   not match at `input.startIndex`. The result is a slice of
                   the original storage; no copying takes place.
    */
    func prefixMatch(in input: Substring) -> Substring? {
        guard let match = try? regex.prefixMatch(in: input) else {
            return nil
        }
        return input[match.range]
    }
}
