import Combine
import Foundation
import PiliPlaybackCore

@MainActor
final class PiliInteractiveController: ObservableObject {
    typealias Loader = @MainActor (Int?) async throws -> PiliInteractiveEdge
    typealias Navigator = @MainActor (Int, String, Bool) async throws -> Void
    @Published private(set) var edge: PiliInteractiveEdge?
    @Published private(set) var choicesVisible = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var history: [PiliInteractiveCheckpoint] = []
    @Published private(set) var savedHistory: [PiliInteractiveCheckpoint] = []
    @Published private(set) var session = InteractiveSession()
    @Published private(set) var plan: InteractiveSession.Plan?
    @Published private(set) var remainingSeconds: Double?
    @Published private(set) var hasEnded = false
    private(set) var graphVersion: Int?
    private weak var viewModel: VideoDetailViewModel?
    private let defaults: UserDefaults
    private var task: Task<Void, Never>?
    private var token = UUID()
    private var context: String?
    private var saveKey: String?
    private var initialCID: Int?
    private var pendingPlaybackEnd = false
    private var loader: Loader?
    private var navigator: Navigator?
    private var pausePlayback: () -> Void = {}
    private var contextIsCurrent: () -> Bool = { true }
    private var retryRequest: RetryRequest?
    private var advanceGuard = InteractiveAdvanceGuard()
    private var presentationActive = true
    private var lastTick: Double?
    private var selectsInteractivePage = false
    private enum RetryRequest {
        case choice(PiliInteractiveEdge.Choice, Bool)
        case restore(PiliInteractiveCheckpoint, [PiliInteractiveCheckpoint])
        case restart
    }
    var isBacktrackingRestricted: Bool { history.contains { $0.noBacktracking } }
    var isOverlayVisible: Bool { choicesVisible || (isLoading && graphVersion != nil) }
    var visibleChoices: [PiliInteractiveEdge.Choice] { plan?.visible ?? [] }
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func selectingInteractivePage(_ selection: () -> Void) {
        selectsInteractivePage = true
        defer { selectsInteractivePage = false }
        selection()
    }
    func willSelectPage() -> Bool {
        guard !selectsInteractivePage, context != nil else { return false }
        reset(context: nil)
        return true
    }

    func prepare(_ viewModel: VideoDetailViewModel) {
        let credential = viewModel.api.requestSnapshot(purpose: .playback)
        let context = "\(viewModel.detail.bvid)|\(credential.playbackCredentialVersion)"
        guard self.context != context, let cid = viewModel.selectedCID else { return }
        reset(context: context)
        self.viewModel = viewModel; initialCID = cid
        let generation = token, video = viewModel.detail
        contextIsCurrent = { [weak viewModel] in
            guard let viewModel else { return false }
            return !viewModel.isPlaybackInvalidatedForNavigation && viewModel.detail.bvid == video.bvid
                && viewModel.api.requestSnapshot(purpose: .playback).playbackCredentialVersion == credential.playbackCredentialVersion
        }
        isLoading = true
        task = Task { [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            do {
                let metadata = try await viewModel.api.fetchPiliPlayerMetadata(bvid: video.bvid, cid: cid)
                guard self.isCurrent(generation) else { return }
                guard let graph = metadata.interaction?.graphVersion, graph > 0 else {
                    self.isLoading = false
                    if self.pendingPlaybackEnd { self.pendingPlaybackEnd = false; viewModel.handlePiliPlaybackEnded() }
                    return
                }
                self.graphVersion = graph
                self.saveKey = "piliplus.interactive.\(credential.currentUserMID ?? 0).\(video.bvid).\(graph)"
                self.loader = { [weak viewModel] edgeID in
                    guard let viewModel else { throw CancellationError() }
                    return try await viewModel.api.fetchPiliInteractiveEdge(bvid: video.bvid, graphVersion: graph, edgeID: edgeID)
                }
                self.navigator = { [weak viewModel] cid, title, automatic in
                    guard let viewModel else { throw CancellationError() }
                    try await viewModel.openPiliInteractivePage(cid: cid, title: title, automatic: automatic)
                }
                self.pausePlayback = { [weak viewModel] in viewModel?.stablePlayerViewModel?.pause() }
                try await self.loadInitial(cid: cid, generation: generation)
            } catch {
                guard self.isCurrent(generation) else { return }
                self.isLoading = false
                if self.graphVersion != nil { self.fail(error) }
                else if self.pendingPlaybackEnd {
                    self.pendingPlaybackEnd = false
                    viewModel.handlePiliPlaybackEnded()
                }
            }
        }
    }

    /// Inject the same I/O boundaries for network-free simulator scenarios.
    func start(context: String, saveKey: String, graphVersion: Int, cid: Int,
               loader: @escaping Loader, navigator: @escaping Navigator,
               pause: @escaping () -> Void = {}, isCurrent: @escaping () -> Bool = { true }) {
        reset(context: context)
        self.graphVersion = graphVersion; self.saveKey = saveKey; initialCID = cid
        self.loader = loader; self.navigator = navigator; pausePlayback = pause; contextIsCurrent = isCurrent
        reloadInitial()
    }
    private func reset(context: String?) {
        task?.cancel(); token = UUID(); self.context = context
        graphVersion = nil; edge = nil; plan = nil; session = InteractiveSession()
        history = []; savedHistory = []; choicesVisible = false; isLoading = false
        errorMessage = nil; remainingSeconds = nil; pendingPlaybackEnd = false; hasEnded = false
        retryRequest = nil; lastTick = nil; saveKey = nil; initialCID = nil; advanceGuard.reset()
        loader = nil; navigator = nil
    }
    private func isCurrent(_ generation: UUID) -> Bool {
        !Task.isCancelled && token == generation && contextIsCurrent()
    }
    private func reloadInitial() {
        guard let cid = initialCID, loader != nil else { return }
        task?.cancel(); token = UUID(); let generation = token
        isLoading = true; errorMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            do { try await self.loadInitial(cid: cid, generation: generation) }
            catch { if self.isCurrent(generation) { self.isLoading = false; self.fail(error) } }
        }
    }
    private func loadInitial(cid: Int, generation: UUID) async throws {
        guard let loader else { return }
        let node = try await loader(nil)
        guard isCurrent(generation) else { return }
        var initial = InteractiveSession()
        try initial.merge(node.hiddenVars)
        let rootCID = node.currentCID ?? cid
        if rootCID != cid { try await navigator?(rootCID, node.title ?? "开始", true) }
        guard isCurrent(generation) else { return }
        initialCID = rootCID; edge = node; session = initial
        history = [.init(edgeID: node.edgeID, cid: rootCID, title: node.title ?? "开始",
                         session: initial, noBacktracking: node.noBacktracking, noTutorial: node.noTutorial)]
        if let saveKey, let data = defaults.data(forKey: saveKey), data.count <= 4 * 1024 * 1024 {
            savedHistory = Array(((try? JSONDecoder().decode([PiliInteractiveCheckpoint].self, from: data)) ?? []).filter { $0.cid > 0 }.suffix(200))
        }
        isLoading = false; errorMessage = nil; choicesVisible = false
        if pendingPlaybackEnd { pendingPlaybackEnd = false; _ = handlePlaybackEnded() }
    }

    func handlePlaybackEnded() -> Bool {
        if isLoading { pendingPlaybackEnd = true; return true }
        guard graphVersion != nil else { return false }
        hasEnded = true
        if errorMessage != nil { choicesVisible = true; return true }
        showDueQuestion(time: 0, duration: 0, ended: true)
        return true
    }
    func setPresentationActive(_ active: Bool) { presentationActive = active; lastTick = nil }
    func updatePlayback(time: Double, duration: Double, now: Double = ProcessInfo.processInfo.systemUptime) {
        guard presentationActive, contextIsCurrent() else { lastTick = nil; return }
        let elapsed = lastTick.map { max(0, now - $0) } ?? 0
        lastTick = now
        guard !isLoading, graphVersion != nil, errorMessage == nil else { return }
        // Seeking back or replaying the same clip dismisses its end screen.
        if hasEnded, time.isFinite, duration.isFinite, duration > 0, time >= 0, time < duration - 1 {
            hasEnded = false; choicesVisible = false; plan = nil; remainingSeconds = nil
        }
        if let plan, choicesVisible, !hasEnded, !plan.question.isDue(time: time, duration: duration, ended: false) {
            choicesVisible = false; remainingSeconds = nil; self.plan = nil
        }
        if !choicesVisible { showDueQuestion(time: time, duration: duration, ended: false) }
        else { advanceCountdown(by: elapsed) }
    }
    private func showDueQuestion(time: Double, duration: Double, ended: Bool) {
        guard let edge else { return }
        if edge.isLeaf || (edge.edges?.questions?.isEmpty ?? true) {
            if ended { choicesVisible = true; plan = nil; remainingSeconds = nil }
            return
        }
        guard !choicesVisible else { return }
        let questions = (edge.edges?.questions ?? []).sorted { ($0.startTimeR ?? 0) > ($1.startTimeR ?? 0) }
        guard let question = questions.first(where: { $0.isDue(time: time, duration: duration, ended: ended) }) else { return }
        let nextPlan = session.plan(question)
        plan = nextPlan
        if nextPlan.isStalled {
            fail(BiliAPIError.api(code: -1, message: "当前剧情没有满足条件的分支，可重试或重新开始"))
            return
        }
        if let automatic = nextPlan.automatic {
            if ended { choose(automatic, automatic: true) }
            return
        }
        choicesVisible = true; remainingSeconds = question.countdown; lastTick = nil
        if question.pauseVideo { pausePlayback() }
    }
    func advanceCountdown(by elapsed: Double) {
        guard presentationActive, elapsed.isFinite, elapsed >= 0, !isLoading, choicesVisible,
              errorMessage == nil, let remainingSeconds, let fallback = plan?.fallback else { return }
        let next = max(0, remainingSeconds - elapsed)
        self.remainingSeconds = next
        if next == 0 { choose(fallback, automatic: true) }
    }

    func choose(_ choice: PiliInteractiveEdge.Choice, automatic: Bool = false) {
        guard !isLoading, contextIsCurrent(), plan?.question.choices?.contains(choice) == true,
              session.allows(choice) else { return }
        retryRequest = .choice(choice, automatic)
        if automatic {
            guard !PiliSleepTimer.shared.shouldStopAtPlaybackEnd() else {
                fail(BiliAPIError.api(code: -1, message: "定时停止已生效，点击重试可继续剧情"))
                return
            }
        } else { PiliSleepTimer.shared.resumeManually() }
        do {
            let next = try session.applying(choice.nativeAction)
            var guardState = advanceGuard
            if automatic { try guardState.record(edgeID: choice.id, session: next) } else { guardState.reset() }
            transition(edgeID: choice.id, cid: choice.cid, title: choice.option ?? "分支",
                       session: next, restore: nil, guardState: guardState, automatic: automatic)
        } catch { fail(error) }
    }
    func revisit(_ checkpoint: PiliInteractiveCheckpoint) {
        guard !isBacktrackingRestricted, let index = history.firstIndex(where: { $0.id == checkpoint.id }) else { return }
        restore(checkpoint, path: Array(history.prefix(index + 1)))
    }
    func restoreSaved() {
        guard !isBacktrackingRestricted, let checkpoint = savedHistory.last else { return }
        restore(checkpoint, path: savedHistory)
    }
    private func restore(_ checkpoint: PiliInteractiveCheckpoint, path: [PiliInteractiveCheckpoint]) {
        guard !isLoading, contextIsCurrent() else { return }
        PiliSleepTimer.shared.resumeManually()
        retryRequest = .restore(checkpoint, path)
        transition(edgeID: checkpoint.edgeID, cid: checkpoint.cid, title: checkpoint.title,
                   session: checkpoint.session ?? InteractiveSession(), restore: (checkpoint, path),
                   guardState: InteractiveAdvanceGuard())
    }
    func retry() {
        guard !isLoading else { return }
        PiliSleepTimer.shared.resumeManually()
        switch retryRequest {
        case let .choice(choice, automatic): choose(choice, automatic: automatic)
        case let .restore(checkpoint, path): restore(checkpoint, path: path)
        case .restart: restart()
        case nil:
            if let checkpoint = history.last { restore(checkpoint, path: history) }
            else if loader != nil { reloadInitial() }
        }
    }
    func restart() {
        guard !isLoading, let initialCID else {
            if let viewModel { context = nil; prepare(viewModel) }
            return
        }
        PiliSleepTimer.shared.resumeManually()
        retryRequest = .restart
        transition(edgeID: nil, cid: initialCID, title: "开始", session: InteractiveSession(),
                   restore: nil, guardState: InteractiveAdvanceGuard(), restarting: true)
    }

    private func transition(edgeID: Int?, cid: Int?, title: String, session candidate: InteractiveSession,
                            restore: (PiliInteractiveCheckpoint, [PiliInteractiveCheckpoint])?,
                            guardState: InteractiveAdvanceGuard, restarting: Bool = false, automatic: Bool = false) {
        guard !isLoading, let loader, let navigator else { return }
        task?.cancel(); token = UUID(); let generation = token
        isLoading = true; choicesVisible = false; errorMessage = nil; remainingSeconds = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let node = try await loader(edgeID)
                guard self.isCurrent(generation) else { return }
                if let requested = edgeID, let actual = node.edgeID, requested != actual { throw BiliAPIError.missingPayload }
                guard let destinationCID = (cid.flatMap { $0 > 0 ? $0 : nil } ?? node.currentCID), destinationCID > 0 else { throw BiliAPIError.missingPayload }
                var next = candidate
                if let restore {
                    if restore.0.session == nil && !node.hiddenVars.isEmpty { throw InteractiveRuleError.unknownVariable("saved state") }
                } else { try next.merge(node.hiddenVars) }
                if automatic, PiliSleepTimer.shared.shouldStopAtPlaybackEnd() {
                    throw BiliAPIError.api(code: -1, message: "定时停止已生效，点击重试可继续剧情")
                }
                try await navigator(destinationCID, node.title ?? title, automatic)
                guard self.isCurrent(generation) else { return }
                let blocked = node.noBacktracking || (restore?.0.noBacktracking ?? false) || (!restarting && self.isBacktrackingRestricted)
                let noTutorial = node.noTutorial || (restore?.0.noTutorial ?? false) || (!restarting && self.history.contains { $0.noTutorial })
                let checkpoint = PiliInteractiveCheckpoint(visitID: restore?.0.visitID ?? UUID(),
                    edgeID: node.edgeID ?? edgeID, cid: destinationCID, title: node.title ?? title,
                    session: next, noBacktracking: blocked, noTutorial: noTutorial)
                var path = restore?.1 ?? (restarting ? [] : self.history)
                if restore != nil { path.removeLast() }
                path.append(checkpoint)
                self.history = Array(path.suffix(200))
                self.edge = node; self.session = next; self.advanceGuard = guardState
                self.plan = nil; self.hasEnded = false; self.pendingPlaybackEnd = false
                self.retryRequest = nil; self.lastTick = nil; self.isLoading = false
                if !noTutorial { self.persistHistory() }
            } catch {
                guard self.isCurrent(generation) else { return }
                self.isLoading = false; self.pendingPlaybackEnd = false; self.fail(error)
            }
        }
    }
    private func persistHistory() {
        guard let saveKey else { return }
        var path = history
        while !path.isEmpty {
            guard let data = try? JSONEncoder().encode(path) else { return }
            if data.count <= 4 * 1024 * 1024 { defaults.set(data, forKey: saveKey); savedHistory = path; return }
            path.removeFirst()
        }
    }
    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription; choicesVisible = true; remainingSeconds = nil
    }
    deinit { task?.cancel() }
}
