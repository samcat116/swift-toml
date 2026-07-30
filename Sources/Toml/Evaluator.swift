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
    Matches input text with a regular expression and turns it into a token.
*/
struct Evaluator: Sendable {
    let pattern: Pattern
    let generator: TokenGenerator
    let push: [String]?
    let pop: Bool

    init(regex: String, generator: @escaping TokenGenerator,
         push: [String]? = nil, pop: Bool = false, multiline: Bool = false) {
        self.pattern = Pattern(regex, dotMatchesNewlines: multiline)
        self.generator = generator
        self.push = push
        self.pop = pop
    }

    /**
        Copy `other`, changing only whether it pops the state stack.

        A value ends the `value` state but not the `array` state -- an array
        stays open for the next element -- so the same value patterns are
        needed with and without the pop. The compiled pattern is shared rather
        than recompiled.
    */
    init(_ other: Evaluator, pop: Bool? = nil, pushingUnder state: String? = nil) {
        self.pattern = other.pattern
        self.generator = other.generator
        // `state` goes *under* whatever this evaluator already pushes, so
        // that a value which opens a nested state -- an array, a multi-line
        // string -- returns to `state` when that state closes.
        self.push = state.map { [$0] + (other.push ?? []) } ?? other.push
        self.pop = pop ?? other.pop
    }

    /**
        Match this evaluator against the start of `content`.

        - Parameter content: Remaining input to match against

        - Returns: The token produced (which may be `nil` for input that is
                   matched but not retained, such as whitespace) along with
                   the index just past the match, or `nil` if this evaluator
                   does not apply. `index` is valid in `content`'s base string.
    */
    func evaluate(_ content: Substring) throws(TomlError)
        -> (token: Token?, index: String.Index)? {
        guard let matched = pattern.prefixMatch(in: content) else {
            return nil
        }
        return (try generator(matched), matched.endIndex)
    }
}
