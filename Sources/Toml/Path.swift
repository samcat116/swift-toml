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
    Abstraction for TOML key paths
*/
public struct Path: Hashable, Sendable {
    internal(set) public var components: [String]

    init(_ components: [String]) {
        self.components = components
    }

    func begins(with prefix: [String]) -> Bool {
        components.starts(with: prefix)
    }

    // `components` is hashed in order. The previous implementation reduced
    // the element hashes with XOR, which is both order-independent and
    // self-cancelling: ["a", "b"] collided with ["b", "a"], and ["a", "a"]
    // collided with []. Every collision degrades the `[Path: Any]` storage
    // and the `Set<Path>` key/table indexes to linear scans.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(components)
    }

    static func + (lhs: Path, rhs: Path) -> Path {
        Path(lhs.components + rhs.components)
    }
}
