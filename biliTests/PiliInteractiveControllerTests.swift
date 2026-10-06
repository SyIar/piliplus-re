import XCTest
import PiliPlaybackCore
@testable import bili

@MainActor
final class PiliInteractiveControllerTests: XCTestCase {
    private let rootJSON = #"{"edge_id":1,"title":"起点","hidden_vars":[{"id_v2":"$score","value":0},{"id_v2":"$dice","type":2,"value":2}],"edges":{"questions":[{"type":1,"duration":5000,"pause_video":1,"choices":[{"id":2,"cid":20,"option":"开门","native_action":"$score=$score+1","is_default":1},{"id":3,"cid":30,"condition":"$score > 10"}]}]}}"#
    private let nextJSON = #"{"edge_id":2,"title":"下一段","hidden_vars":[{"id_v2":"$score","value":0},{"id_v2":"$dice","value":9,"type":2}],"edges":{"questions":[{"type":1,"choices":[{"id":4,"cid":40,"option":"结局","condition":"$score == 1"}]}]}}"#
    private func decode(_ value: String) throws -> PiliInteractiveEdge {
        try JSONDecoder().decode(PiliInteractiveEdge.self, from: Data(value.utf8))
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Interactive transition did not settle")
    }
    private func settle(_ controller: PiliInteractiveController) async throws {
        try await waitUntil { !controller.isLoading }
    }
    private func defaults() -> UserDefaults {
        let name = "PiliInteractiveControllerTests.\(UUID().uuidString)"
        let value = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return value
    }

    func testFailedBranchAndRetryCommitVariablesOnlyAfterPlaybackSucceeds() async throws {
        let root = try decode(rootJSON), next = try decode(nextJSON), defaults = defaults()
        let controller = PiliInteractiveController(defaults: defaults)
        var rejectsNode = true, rejectsPlayback = true, opened: [Int] = []
        controller.start(context: "a", saveKey: "save.a", graphVersion: 1, cid: 10, loader: { id in
            if id == nil || id == 1 { return root }
            if rejectsNode { throw BiliAPIError.emptyData }
            return next
        }, navigator: { cid, _ in
            if rejectsPlayback { throw BiliAPIError.emptyData }
            opened.append(cid)
        })
        try await settle(controller)
        XCTAssertTrue(controller.handlePlaybackEnded())
        let choice = try XCTUnwrap(controller.visibleChoices.first)
        XCTAssertEqual(controller.visibleChoices.map(\.id), [2])
        controller.choose(choice)
        try await settle(controller)
        XCTAssertEqual(controller.history.count, 1)
        XCTAssertEqual(controller.session.values["score"], 0)
        XCTAssertNil(defaults.data(forKey: "save.a"))
        rejectsNode = false
        controller.retry()
        try await settle(controller)
        XCTAssertEqual(controller.history.count, 1)
        XCTAssertEqual(controller.session.values["score"], 0)
        rejectsPlayback = false
        controller.retry()
        try await settle(controller)
        XCTAssertEqual(opened, [20])
        XCTAssertEqual(controller.history.count, 2)
        XCTAssertEqual(controller.session.values["score"], 1)
        XCTAssertEqual(controller.session.values["dice"], 2)
        XCTAssertNotNil(defaults.data(forKey: "save.a"))
    }

    func testFailedRevisitKeepsCurrentPathAndSuccessfulRevisitRestoresVariables() async throws {
        let root = try decode(rootJSON), next = try decode(nextJSON), controller = PiliInteractiveController(defaults: defaults())
        var rejectsRoot = false
        controller.start(context: "a", saveKey: "save", graphVersion: 1, cid: 10, loader: { id in
            if id == nil || id == 1 {
                if rejectsRoot { throw BiliAPIError.emptyData }
                return root
            }
            return next
        }, navigator: { _, _ in })
        try await settle(controller)
        let checkpoint = try XCTUnwrap(controller.history.first)
        _ = controller.handlePlaybackEnded()
        controller.choose(try XCTUnwrap(controller.visibleChoices.first))
        try await settle(controller)
        rejectsRoot = true
        controller.revisit(checkpoint)
        try await settle(controller)
        XCTAssertEqual(controller.history.count, 2)
        XCTAssertEqual(controller.session.values["score"], 1)
        rejectsRoot = false
        controller.retry()
        try await settle(controller)
        XCTAssertEqual(controller.history.count, 1)
        XCTAssertEqual(controller.history.first?.id, checkpoint.id)
        XCTAssertEqual(controller.session.values["score"], 0)
        XCTAssertEqual(controller.session.values["dice"], 2)
    }

    func testCountdownFreezesOffscreenAndAuthorCanBlockBacktracking() async throws {
        let root = try decode(rootJSON)
        let leaf = try decode(#"{"edge_id":2,"title":"结束","is_leaf":1,"no_backtracking":1}"#)
        let controller = PiliInteractiveController(defaults: defaults())
        controller.start(context: "a", saveKey: "save", graphVersion: 1, cid: 10,
                         loader: { $0 == nil || $0 == 1 ? root : leaf }, navigator: { _, _ in })
        try await settle(controller)
        let checkpoint = try XCTUnwrap(controller.history.first)
        _ = controller.handlePlaybackEnded()
        controller.setPresentationActive(false)
        controller.advanceCountdown(by: 10)
        XCTAssertEqual(controller.remainingSeconds, 5)
        controller.setPresentationActive(true)
        controller.advanceCountdown(by: 6)
        try await settle(controller)
        XCTAssertEqual(controller.edge?.edgeID, 2)
        XCTAssertTrue(controller.isBacktrackingRestricted)
        controller.revisit(checkpoint)
        XCTAssertEqual(controller.history.count, 2)
        XCTAssertTrue(controller.handlePlaybackEnded(), "An interactive ending must not fall into normal autoplay")
        XCTAssertTrue(controller.hasEnded)
        XCTAssertNil(controller.plan)
    }

    func testAutomaticNodeWaitsForTheClipToFinish() async throws {
        let root = try decode(#"{"edge_id":1,"edges":{"questions":[{"type":0,"choices":[{"id":2,"cid":20,"is_hidden":1}]}]}}"#)
        let leaf = try decode(#"{"edge_id":2,"is_leaf":1}"#)
        let controller = PiliInteractiveController(defaults: defaults())
        var opened = 0
        controller.start(context: "a", saveKey: "save", graphVersion: 1, cid: 10,
                         loader: { $0 == nil ? root : leaf }, navigator: { _, _ in opened += 1 })
        try await settle(controller)
        controller.updatePlayback(time: 1, duration: 10)
        XCTAssertEqual(opened, 0)
        XCTAssertFalse(controller.choicesVisible)
        _ = controller.handlePlaybackEnded()
        try await settle(controller)
        XCTAssertEqual(opened, 1)
        XCTAssertEqual(controller.edge?.edgeID, 2)
    }

    func testNewAccountContextDiscardsAnOlderNodeResponse() async throws {
        let old = try decode(rootJSON), fresh = try decode(#"{"edge_id":99,"is_leaf":1}"#)
        let controller = PiliInteractiveController(defaults: defaults())
        var continuation: CheckedContinuation<PiliInteractiveEdge, Error>?
        controller.start(context: "old", saveKey: "old.save", graphVersion: 1, cid: 10,
                         loader: { _ in try await withCheckedThrowingContinuation { continuation = $0 } },
                         navigator: { _, _ in XCTFail("An obsolete context must never navigate") })
        try await waitUntil { continuation != nil }
        controller.start(context: "new", saveKey: "new.save", graphVersion: 2, cid: 99,
                         loader: { _ in fresh }, navigator: { _, _ in })
        try await settle(controller)
        continuation?.resume(returning: old)
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(controller.edge?.edgeID, 99)
        XCTAssertEqual(controller.history.map(\.cid), [99])
        XCTAssertTrue(controller.session.values.isEmpty)
    }

    func testSavedStateRestoresVariablesAndSeparatesGraphKeys() async throws {
        let root = try decode(rootJSON), next = try decode(nextJSON), defaults = defaults()
        let controller = PiliInteractiveController(defaults: defaults)
        controller.start(context: "graph1", saveKey: "account.1.video.graph1", graphVersion: 1, cid: 10,
                         loader: { $0 == nil || $0 == 1 ? root : next }, navigator: { _, _ in })
        try await settle(controller)
        _ = controller.handlePlaybackEnded()
        controller.choose(try XCTUnwrap(controller.visibleChoices.first))
        try await settle(controller)
        let restored = PiliInteractiveController(defaults: defaults)
        restored.start(context: "graph1", saveKey: "account.1.video.graph1", graphVersion: 1, cid: 10,
                       loader: { $0 == nil || $0 == 1 ? root : next }, navigator: { _, _ in })
        try await settle(restored)
        restored.restoreSaved()
        try await settle(restored)
        XCTAssertEqual(restored.session.values["score"], 1)
        XCTAssertEqual(restored.history.count, 2)
        restored.start(context: "graph2", saveKey: "account.1.video.graph2", graphVersion: 2, cid: 10,
                       loader: { _ in root }, navigator: { _, _ in })
        try await settle(restored)
        XCTAssertTrue(restored.savedHistory.isEmpty)
    }

    func testRewindingDismissesEndingAndChoicesCanAppearAgain() async throws {
        let root = try decode(rootJSON), controller = PiliInteractiveController(defaults: defaults())
        controller.start(context: "a", saveKey: "save", graphVersion: 1, cid: 10,
                         loader: { _ in root }, navigator: { _, _ in })
        try await settle(controller)
        _ = controller.handlePlaybackEnded()
        XCTAssertTrue(controller.choicesVisible)
        controller.updatePlayback(time: 2, duration: 10)
        XCTAssertFalse(controller.hasEnded)
        XCTAssertFalse(controller.choicesVisible)
        _ = controller.handlePlaybackEnded()
        XCTAssertTrue(controller.choicesVisible)
        XCTAssertEqual(controller.remainingSeconds, 5)
    }

    func testSavedRestrictedEndingCannotBeUsedToBypassBacktracking() async throws {
        let root = try decode(rootJSON)
        let leaf = try decode(#"{"edge_id":2,"is_leaf":1,"no_backtracking":1}"#)
        let defaults = defaults(), first = PiliInteractiveController(defaults: defaults)
        let loader: PiliInteractiveController.Loader = { $0 == nil || $0 == 1 ? root : leaf }
        first.start(context: "a", saveKey: "save", graphVersion: 1, cid: 10,
                    loader: loader, navigator: { _, _ in })
        try await settle(first)
        _ = first.handlePlaybackEnded()
        first.choose(try XCTUnwrap(first.visibleChoices.first))
        try await settle(first)
        let restored = PiliInteractiveController(defaults: defaults)
        restored.start(context: "a", saveKey: "save", graphVersion: 1, cid: 10,
                       loader: loader, navigator: { _, _ in })
        try await settle(restored)
        restored.restoreSaved()
        try await settle(restored)
        XCTAssertTrue(restored.isBacktrackingRestricted)
        restored.revisit(try XCTUnwrap(restored.history.first))
        XCTAssertEqual(restored.edge?.edgeID, 2)
        restored.restart()
        try await settle(restored)
        XCTAssertFalse(restored.isBacktrackingRestricted)
        XCTAssertEqual(restored.history.count, 1)
        XCTAssertEqual(restored.session.values["score"], 0)
    }
}
