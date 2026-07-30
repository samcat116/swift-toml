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
    Convert an input string of TOML to a stream of tokens
*/
struct Lexer {
    let input: String
    let grammar: [String: [Evaluator]]

    init(input: String, grammar: [String: [Evaluator]] = Grammar.shared.grammar) {
        self.input = input
        self.grammar = grammar
    }

    func tokenize() throws(TomlError) -> [Token] {
        var tokens = [Token]()
        var stack = ["root"]

        // The scan walks a cursor forward through `input` rather than
        // re-slicing a `String` copy of the remaining text on every token.
        // The latter is quadratic: each token copies the whole rest of the
        // document.
        var cursor = input.startIndex

        while cursor < input.endIndex {
            guard let state = stack.last, let evaluators = grammar[state] else {
                throw TomlError.syntaxError("Unknown lexer state: \(stack.last ?? "<empty>")")
            }

            var matched = false
            for evaluator in evaluators {
                guard let (token, next) = try evaluator.evaluate(input[cursor...]) else {
                    continue
                }

                if let token {
                    tokens.append(token)
                }

                if evaluator.pop {
                    guard !stack.isEmpty else {
                        throw TomlError.syntaxError("Unbalanced \(state) at: \(input[cursor...])")
                    }
                    stack.removeLast()
                }

                if let push = evaluator.push {
                    stack.append(contentsOf: push)
                }

                // A zero-length match that also leaves the state stack alone
                // makes no progress and would spin forever. Treat it as a
                // syntax error rather than hanging on malformed input.
                if next == cursor && !evaluator.pop && evaluator.push == nil {
                    throw TomlError.syntaxError("Made no progress at: \(input[cursor...])")
                }

                cursor = next
                matched = true
                break
            }

            if !matched {
                throw TomlError.syntaxError(String(input[cursor...]))
            }
        }

        // Every construct that opens a state closes it again, so anything
        // left on the stack at the end of the document was never closed: an
        // array without its `]`, an inline table without its `}`, a string
        // without its final quote. These used to be accepted, and produced
        // whatever partial document the truncated input happened to describe.
        // A document that ends immediately after a value or a table header,
        // with no final newline, is left waiting for that newline in `eol`.
        if stack != ["root"] && stack != ["root", "eol"] {
            throw TomlError.syntaxError(
                "Unterminated \(stack.last ?? "document") at end of document")
        }

        return tokens
    }
}
