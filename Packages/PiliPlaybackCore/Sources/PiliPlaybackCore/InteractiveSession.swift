import Foundation

public struct InteractiveSession: Codable, Equatable, Sendable {
    public private(set) var values: [String: Double] = [:]
    public private(set) var metadata: [String: InteractiveNode.Variable] = [:]
    private var touched: Set<String> = []
    private var aliases: [String: String] = [:]
    public init() {}

    public mutating func merge(_ variables: [InteractiveNode.Variable]) throws {
        for variable in variables where !variable.key.isEmpty {
            let key = variable.key
            metadata[key] = variable
            if let legacy = variable.id, InteractiveExpression.canonical(legacy) != key {
                aliases[InteractiveExpression.canonical(legacy)] = key
            }
            if values[key] == nil || (variable.type != 2 && !variable.skipOverwrite && !touched.contains(key)) {
                values[key] = variable.value ?? values[key] ?? 0
            }
        }
        synchronizeAliases()
        guard values.count <= 512, metadata.count <= 512 else { throw InteractiveRuleError.resourceLimit }
    }
    public func allows(_ choice: InteractiveNode.Choice) -> Bool {
        choice.id > 0 && (try? InteractiveExpression.condition(choice.condition, values: values)) == true
    }
    public func applying(_ action: String?) throws -> Self {
        let result = try InteractiveExpression.action(action, values: values, aliases: aliases)
        var next = self
        next.values = result.values
        next.touched.formUnion(result.written)
        next.synchronizeAliases()
        return next
    }
    private mutating func synchronizeAliases() {
        for (alias, key) in aliases { values[alias] = values[key] }
    }

    public struct Plan: Sendable {
        public let question: InteractiveNode.Question
        public let visible: [InteractiveNode.Choice]
        public let automatic: InteractiveNode.Choice?
        public let fallback: InteractiveNode.Choice?
        public var isStalled: Bool { visible.isEmpty && automatic == nil }
    }
    public func plan(_ question: InteractiveNode.Question) -> Plan {
        var seen = Set<Int>()
        let allowed = (question.choices ?? []).filter { allows($0) && seen.insert($0.id).inserted }
        let visible = allowed.filter { !$0.isHidden }
        // Defaults still obey conditions: a malformed/false condition cannot
        // accidentally unlock a branch when the timer expires.
        let fallback = allowed.first { $0.isDefault } ?? visible.first ?? allowed.first
        let automatic = question.isAutomatic || visible.isEmpty ? (allowed.first { $0.isDefault } ?? allowed.first) : nil
        return Plan(question: question, visible: question.isAutomatic ? [] : visible, automatic: automatic, fallback: fallback)
    }
}

/// A single automatic chain is bounded even when a bad graph mutates a variable
/// on every loop. User choices start a fresh chain.
public struct InteractiveAdvanceGuard: Sendable {
    private var visited: Set<String> = []
    private var count = 0
    public init() {}
    public mutating func reset() { visited.removeAll(); count = 0 }
    public mutating func record(edgeID: Int, session: InteractiveSession) throws {
        guard count < 32 else { throw InteractiveRuleError.resourceLimit }
        let signature = String(edgeID) + "|" + session.values.keys.sorted().map { "\($0)=\(session.values[$0]!)" }.joined(separator: ";")
        guard visited.insert(signature).inserted else { throw InteractiveRuleError.resourceLimit }
        count += 1
    }
}
