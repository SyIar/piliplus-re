import Foundation
import Testing
@testable import PiliPlaybackCore

private func node(_ json: String) throws -> InteractiveNode {
    try JSONDecoder().decode(InteractiveNode.self, from: Data(json.utf8))
}

@Test func interactiveArithmeticPrecedenceAndShortCircuit() throws {
    #expect(try InteractiveExpression.evaluate("2 + 3 * 4 - 8 / 2", values: [:]) == 10)
    #expect(try InteractiveExpression.evaluate("-(.5 + 1e2) % 3", values: [:]) == -1.5)
    #expect(try InteractiveExpression.condition("$score >= 2 && ($score < 4 || $missing)", values: ["score": 3]))
    #expect(try InteractiveExpression.evaluate("1 || 1 / 0", values: [:]) == 1)
    #expect(try InteractiveExpression.evaluate("0 && $missing", values: [:]) == 0)
    #expect(throws: InteractiveRuleError.self) { try InteractiveExpression.evaluate("$missing + 1", values: [:]) }
    #expect(throws: InteractiveRuleError.self) { try InteractiveExpression.evaluate("1 / 0", values: [:]) }
}

@Test func interactiveActionsAreAtomicAndRejectUntrustedLanguage() throws {
    let original = ["a": 1.0]
    let result = try InteractiveExpression.action("$a=$a+2;$b=$a*3;", values: original)
    #expect(result.values["a"] == 3 && result.values["b"] == 9)
    #expect(original == ["a": 1])
    #expect(throws: InteractiveRuleError.self) { try InteractiveExpression.action("$a=5;$b=1/0", values: original) }
    for invalid in ["foo()", "a.b", "$", "1e+", "1;2", "$a=2", "1e999", String(repeating: "(", count: 100) + "1" + String(repeating: ")", count: 100)] {
        #expect(throws: InteractiveRuleError.self) { try InteractiveExpression.evaluate(invalid, values: original) }
    }
    #expect(throws: InteractiveRuleError.self) { try InteractiveExpression.evaluate(String(repeating: "1+", count: 10_000) + "1", values: original) }
}

@Test func interactiveVariablesPreserveActionsRandomValuesAndSnapshotAliases() throws {
    let first = try node(#"{"hidden_vars":[{"id":"old","id_v2":"$score","value":"1","type":1},{"id_v2":"$dice","value":3,"type":2},{"id_v2":"$server","value":1},{"id_v2":"$sticky","value":8,"skip_overwrite":1}]}"#)
    var session = InteractiveSession()
    try session.merge(first.hiddenVars)
    session = try session.applying("$old=2;$score=$old+1")
    #expect(session.values["score"] == 3 && session.values["old"] == 3)
    let refreshed = try node(#"{"hidden_vars":[{"id":"old","id_v2":"$score","value":0},{"id_v2":"$dice","value":9,"type":2},{"id_v2":"$server","value":7},{"id_v2":"$sticky","value":1,"skip_overwrite":1}]}"#)
    let saved = try JSONEncoder().encode(session)
    var restored = try JSONDecoder().decode(InteractiveSession.self, from: saved)
    try restored.merge(refreshed.hiddenVars)
    #expect(restored.values["score"] == 3)
    #expect(restored.values["dice"] == 3)
    #expect(restored.values["server"] == 7)
    #expect(restored.values["sticky"] == 8)
}

@Test func interactivePlansHonorConditionsHiddenChoicesAndDefaults() throws {
    let value = try node(#"{"edges":{"questions":[{"type":1,"duration":"5000","pause_video":true,"choices":[{"id":"1","cid":10,"condition":"$score > 10","is_default":1},{"id":2,"cid":"20","condition":"$score == 1"},{"id":3,"cid":30,"is_hidden":1}]},{"type":0,"choices":[{"id":4,"cid":40,"is_hidden":1}]}]},"hidden_vars":[{"id_v2":"$score","value":1}]}"#)
    var session = InteractiveSession()
    try session.merge(value.hiddenVars)
    let questions = try #require(value.edges?.questions)
    let plan = session.plan(questions[0])
    #expect(plan.visible.map(\.id) == [2])
    #expect(plan.fallback?.id == 2)
    #expect(plan.question.countdown == 5)
    #expect(plan.question.pauseVideo)
    #expect(session.plan(questions[1]).automatic?.id == 4)
    #expect(value.choices.count == 4)
}

@Test func interactiveQuestionTimingAndHotspotCoordinatesUseVideoSpace() throws {
    let value = try node(#"{"edges":{"questions":[{"type":2,"start_time_r":300,"choices":[{"id":2,"x":192,"y":900,"text_align":1},{"id":3,"x":-1,"y":500}]}]}}"#)
    let question = try #require(value.edges?.questions?.first)
    #expect(!question.isDue(time: 8, duration: 10, ended: false))
    #expect(question.isDue(time: 9.8, duration: 10, ended: false))
    #expect(question.isDue(time: 0, duration: 0, ended: true))
    #expect(!question.isDue(time: .nan, duration: 10, ended: false))
    let point = try #require(question.choices?.first?.normalizedHotspot(width: 1920, height: 1000))
    #expect(abs(point.x - 0.1) < 0.0001 && abs(point.y - 0.1) < 0.0001)
    #expect(question.choices?[1].normalizedHotspot(width: 1920, height: 1000) == nil)
}

@Test func automaticInteractiveChainsCannotLoopForever() throws {
    var guardState = InteractiveAdvanceGuard(), session = InteractiveSession()
    try guardState.record(edgeID: 1, session: session)
    #expect(throws: InteractiveRuleError.self) { try guardState.record(edgeID: 1, session: session) }
    guardState.reset()
    for value in 0..<32 {
        session = try session.applying("$counter=\(value)")
        try guardState.record(edgeID: 1, session: session)
    }
    session = try session.applying("$counter=100")
    #expect(throws: InteractiveRuleError.self) { try guardState.record(edgeID: 1, session: session) }
}
