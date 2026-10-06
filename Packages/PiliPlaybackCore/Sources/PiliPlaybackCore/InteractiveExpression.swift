import Foundation

public enum InteractiveRuleError: Error, Equatable, LocalizedError {
    case malformedExpression, unknownVariable(String), divisionByZero, resourceLimit, nonFiniteValue
    public var errorDescription: String? {
        switch self {
        case .malformedExpression: "互动视频的剧情表达式无法识别"
        case .unknownVariable: "互动视频缺少必要的剧情变量"
        case .divisionByZero: "互动视频的剧情运算无效"
        case .resourceLimit: "互动视频的剧情规则超出处理范围"
        case .nonFiniteValue: "互动视频的剧情变量数值无效"
        }
    }
}

/// Deliberately small arithmetic language. Server text is never executed as
/// JavaScript, NSPredicate, or native code. Both parsing and evaluation are bounded.
public enum InteractiveExpression {
    public struct ActionResult: Sendable {
        public let values: [String: Double]
        public let written: Set<String>
    }
    public static func canonical(_ name: String) -> String {
        name.hasPrefix("$") ? String(name.dropFirst()) : name
    }
    public static func evaluate(_ source: String, values: [String: Double]) throws -> Double {
        var parser = try Parser(source)
        let expression = try parser.expression()
        guard parser.current == .end else { throw InteractiveRuleError.malformedExpression }
        return try expression.evaluate(values, depth: 0)
    }
    public static func condition(_ source: String?, values: [String: Double]) throws -> Bool {
        guard let source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        return try evaluate(source, values: values) != 0
    }
    public static func action(_ source: String?, values: [String: Double], aliases: [String: String] = [:]) throws -> ActionResult {
        guard let source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ActionResult(values: values, written: [])
        }
        var parser = try Parser(source), next = values, written = Set<String>(), statements = 0
        while parser.current != .end {
            if parser.take(.symbol(";")) { continue }
            statements += 1
            guard statements <= 128 else { throw InteractiveRuleError.resourceLimit }
            var target: String?
            if case let .name(name) = parser.current, parser.peek == .symbol("=") {
                target = aliases[canonical(name)] ?? canonical(name); parser.index += 2
            }
            let expression = try parser.expression()
            let value = try expression.evaluate(next, depth: 0)
            if let target {
                next[target] = value; written.insert(target)
                for (alias, key) in aliases where key == target { next[alias] = value }
                guard next.count <= 512 else { throw InteractiveRuleError.resourceLimit }
            }
            guard parser.current == .end || parser.take(.symbol(";")) else { throw InteractiveRuleError.malformedExpression }
        }
        return ActionResult(values: next, written: written)
    }

    private enum Token: Equatable {
        case number(Double), name(String), symbol(String), end
        var precedence: Int {
            switch self {
            case .symbol("||"): 1
            case .symbol("&&"): 2
            case .symbol("=="), .symbol("!="): 3
            case .symbol("<"), .symbol("<="), .symbol(">"), .symbol(">="): 4
            case .symbol("+"), .symbol("-"): 5
            case .symbol("*"), .symbol("/"), .symbol("%"): 6
            default: -1
            }
        }
    }
    private indirect enum Expression {
        case number(Double), variable(String), unary(String, Expression), binary(String, Expression, Expression)
        func evaluate(_ values: [String: Double], depth: Int) throws -> Double {
            guard depth <= 64 else { throw InteractiveRuleError.resourceLimit }
            let result: Double
            switch self {
            case let .number(value): result = value
            case let .variable(name):
                let key = canonical(name)
                guard let value = values[key] ?? values["$" + key] else { throw InteractiveRuleError.unknownVariable(key) }
                result = value
            case let .unary(op, expression):
                let value = try expression.evaluate(values, depth: depth + 1)
                switch op {
                case "-": result = -value
                case "+": result = value
                case "!": result = value == 0 ? 1 : 0
                default: throw InteractiveRuleError.malformedExpression
                }
            case let .binary(op, left, right):
                let lhs = try left.evaluate(values, depth: depth + 1)
                if op == "&&", lhs == 0 { return 0 }
                if op == "||", lhs != 0 { return 1 }
                let rhs = try right.evaluate(values, depth: depth + 1)
                switch op {
                case "+": result = lhs + rhs
                case "-": result = lhs - rhs
                case "*": result = lhs * rhs
                case "/":
                    guard rhs != 0 else { throw InteractiveRuleError.divisionByZero }; result = lhs / rhs
                case "%":
                    guard rhs != 0 else { throw InteractiveRuleError.divisionByZero }; result = lhs.truncatingRemainder(dividingBy: rhs)
                case "==": result = lhs == rhs ? 1 : 0
                case "!=": result = lhs != rhs ? 1 : 0
                case ">": result = lhs > rhs ? 1 : 0
                case ">=": result = lhs >= rhs ? 1 : 0
                case "<": result = lhs < rhs ? 1 : 0
                case "<=": result = lhs <= rhs ? 1 : 0
                case "&&", "||": result = rhs != 0 ? 1 : 0
                default: throw InteractiveRuleError.malformedExpression
                }
            }
            guard result.isFinite else { throw InteractiveRuleError.nonFiniteValue }
            return result
        }
    }
    private struct Parser {
        let tokens: [Token]
        var index = 0
        var current: Token { tokens[index] }
        var peek: Token { tokens[min(index + 1, tokens.count - 1)] }
        init(_ source: String) throws {
            guard source.utf8.count <= 16_384 else { throw InteractiveRuleError.resourceLimit }
            let chars = Array(source)
            var cursor = 0, tokens: [Token] = []
            func digit(_ char: Character) -> Bool { char >= "0" && char <= "9" }
            func word(_ char: Character) -> Bool { char.isLetter || char.isNumber || char == "_" }
            while cursor < chars.count {
                let ch = chars[cursor]
                if ch.isWhitespace { cursor += 1; continue }
                let start = cursor
                if digit(ch) || (ch == "." && cursor + 1 < chars.count && digit(chars[cursor + 1])) {
                    while cursor < chars.count && digit(chars[cursor]) { cursor += 1 }
                    if cursor < chars.count && chars[cursor] == "." {
                        cursor += 1
                        while cursor < chars.count && digit(chars[cursor]) { cursor += 1 }
                    }
                    if cursor < chars.count && (chars[cursor] == "e" || chars[cursor] == "E") {
                        cursor += 1
                        if cursor < chars.count && (chars[cursor] == "+" || chars[cursor] == "-") { cursor += 1 }
                        let exponentStart = cursor
                        while cursor < chars.count && digit(chars[cursor]) { cursor += 1 }
                        guard cursor > exponentStart else { throw InteractiveRuleError.malformedExpression }
                    }
                    guard let number = Double(String(chars[start..<cursor])), number.isFinite else { throw InteractiveRuleError.nonFiniteValue }
                    tokens.append(.number(number))
                } else if ch == "$" || ch.isLetter || ch == "_" {
                    cursor += 1
                    while cursor < chars.count && word(chars[cursor]) { cursor += 1 }
                    let name = String(chars[start..<cursor])
                    guard name != "$" else { throw InteractiveRuleError.malformedExpression }
                    if name == "true" { tokens.append(.number(1)) }
                    else if name == "false" { tokens.append(.number(0)) }
                    else { tokens.append(.name(name)) }
                } else {
                    let pair = cursor + 1 < chars.count ? String(chars[cursor...cursor + 1]) : ""
                    if ["==", "!=", ">=", "<=", "&&", "||"].contains(pair) {
                        tokens.append(.symbol(pair)); cursor += 2
                    } else if "+-*/%=!<>() ;".contains(ch) {
                        tokens.append(.symbol(String(ch))); cursor += 1
                    } else { throw InteractiveRuleError.malformedExpression }
                }
                guard tokens.count <= 2_048 else { throw InteractiveRuleError.resourceLimit }
            }
            tokens.append(.end); self.tokens = tokens
        }
        mutating func take(_ token: Token) -> Bool {
            guard current == token else { return false }; index += 1; return true
        }
        mutating func expression(minimum: Int = 0, depth: Int = 0) throws -> Expression {
            guard depth <= 64 else { throw InteractiveRuleError.resourceLimit }
            var left: Expression
            switch current {
            case let .number(value): index += 1; left = .number(value)
            case let .name(name): index += 1; left = .variable(name)
            case .symbol("("):
                index += 1; left = try expression(depth: depth + 1)
                guard take(.symbol(")")) else { throw InteractiveRuleError.malformedExpression }
            case .symbol("+"), .symbol("-"), .symbol("!"):
                guard case let .symbol(op) = current else { throw InteractiveRuleError.malformedExpression }
                index += 1; left = .unary(op, try expression(minimum: 7, depth: depth + 1))
            default: throw InteractiveRuleError.malformedExpression
            }
            while current.precedence >= minimum {
                let precedence = current.precedence
                guard case let .symbol(op) = current else { break }
                index += 1
                left = .binary(op, left, try expression(minimum: precedence + 1, depth: depth + 1))
            }
            return left
        }
    }
}
