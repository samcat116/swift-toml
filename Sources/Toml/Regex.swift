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

private let expressionsCache = ExpressionCache()

private final class ExpressionCache: @unchecked Sendable {
    private var expressions = [String: NSRegularExpression]()
    private let lock = NSLock()
    
    func expression(for pattern: String, options: NSRegularExpression.Options) -> NSRegularExpression {
        lock.lock()
        defer { lock.unlock() }
        
        if let cachedRegexp = expressions[pattern] {
            return cachedRegexp
        } else {
            let expression = try! NSRegularExpression(pattern: "^\(pattern)", options: options)
            expressions[pattern] = expression
            return expression
        }
    }
}

extension String {
    func match(_ regex: String, options: NSRegularExpression.Options = []) -> String? {
        let expression = expressionsCache.expression(for: regex, options: options)
        
        let range = expression.rangeOfFirstMatch(in: self, options: [],
            range: NSMakeRange(0, self.count))
        if range.location != NSNotFound {
            return NSString(string: self).substring(with: range)
        }
        return nil
    }
}
