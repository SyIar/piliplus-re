import Combine
import Foundation

@MainActor
final class PiliInteractiveController: ObservableObject {
    @Published private(set) var edge: PiliInteractiveEdge?
    @Published private(set) var choicesVisible = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var history: [PiliInteractiveCheckpoint] = []
    @Published private(set) var savedHistory: [PiliInteractiveCheckpoint] = []
    private(set) var graphVersion: Int?
    private weak var viewModel: VideoDetailViewModel?
    private var task: Task<Void, Never>?
    private var token = UUID()
    private var context: String?
    private var pendingPlaybackEnd = false
    private var saveKey: String?
    private var activeCheckpoint: PiliInteractiveCheckpoint?

    func prepare(_ viewModel: VideoDetailViewModel) {
        let credential = viewModel.api.requestSnapshot(purpose: .playback)
        let context = "\(viewModel.detail.bvid)|\(credential.playbackCredentialVersion)"
        guard self.context != context, let cid = viewModel.selectedCID else { return }
        task?.cancel(); token = UUID(); self.context = context; self.viewModel = viewModel
        pendingPlaybackEnd = false; graphVersion = nil; edge = nil; choicesVisible = false; errorMessage = nil; history = []; savedHistory = []
        let token = token, video = viewModel.detail
        isLoading = true
        task = Task { [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            defer {
                if self.token == token {
                    self.isLoading = false; self.task = nil
                    if self.pendingPlaybackEnd, !viewModel.isPlaybackInvalidatedForNavigation {
                        self.pendingPlaybackEnd = false
                        viewModel.handlePiliPlaybackEnded()
                    }
                }
            }
            do {
                let metadata = try await viewModel.api.fetchPiliPlayerMetadata(bvid: video.bvid, cid: cid)
                guard !Task.isCancelled, self.token == token, !viewModel.isPlaybackInvalidatedForNavigation else { return }
                guard let graph = metadata.interaction?.graphVersion, graph > 0 else { return }
                self.graphVersion = graph
                self.saveKey = "piliplus.interactive.\(credential.currentUserMID ?? 0).\(video.bvid).\(graph)"
                if let key = self.saveKey, let data = UserDefaults.standard.data(forKey: key) {
                    self.savedHistory = (try? JSONDecoder().decode([PiliInteractiveCheckpoint].self, from: data)) ?? []
                }
                let first = PiliInteractiveCheckpoint(edgeID: nil, cid: cid, title: "开始")
                self.activeCheckpoint = first; self.history = [first]
                let edge = try await viewModel.api.fetchPiliInteractiveEdge(bvid: video.bvid, graphVersion: graph, edgeID: nil)
                guard !Task.isCancelled, self.token == token, !viewModel.isPlaybackInvalidatedForNavigation else { return }
                self.edge = edge
            } catch {
                guard !Task.isCancelled, self.token == token else { return }
                if self.graphVersion != nil { self.errorMessage = "互动分支加载失败：\(error.localizedDescription)" }
            }
        }
    }
    func handlePlaybackEnded() -> Bool {
        if isLoading { pendingPlaybackEnd = true; return true }
        guard graphVersion != nil else { return false }
        if isLoading || errorMessage != nil { choicesVisible = true; return true }
        guard edge?.choices.isEmpty == false else { return false }
        choicesVisible = true
        return true
    }
    func choose(_ choice: PiliInteractiveEdge.Choice) {
        guard let cid = choice.cid, cid > 0 else { return }
        open(.init(edgeID: choice.id, cid: cid, title: choice.option ?? "分支"), append: true)
    }
    func revisit(_ checkpoint: PiliInteractiveCheckpoint) {
        if let index = history.firstIndex(where: { $0.id == checkpoint.id }) { history = Array(history.prefix(index + 1)) }
        open(checkpoint, append: false)
    }
    func restoreSaved() {
        guard let last = savedHistory.last else { return }
        history = savedHistory
        open(last, append: false)
    }
    func retry() {
        guard let activeCheckpoint else { return }
        open(activeCheckpoint, append: false)
    }
    private func open(_ checkpoint: PiliInteractiveCheckpoint, append: Bool) {
        guard !isLoading, let viewModel, !viewModel.isPlaybackInvalidatedForNavigation, let graphVersion else { return }
        task?.cancel(); token = UUID(); let token = token
        isLoading = true; errorMessage = nil; choicesVisible = false
        let bvid = viewModel.detail.bvid
        task = Task { [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            defer { if self.token == token { self.isLoading = false; self.task = nil } }
            do {
                // Obtain the destination graph before replacing playback, so a failed request is retryable.
                let edge = try await viewModel.api.fetchPiliInteractiveEdge(bvid: bvid, graphVersion: graphVersion, edgeID: checkpoint.edgeID)
                guard !Task.isCancelled, self.token == token, viewModel.detail.bvid == bvid,
                      !viewModel.isPlaybackInvalidatedForNavigation else { return }
                self.edge = edge; self.activeCheckpoint = checkpoint
                if append { self.history.append(checkpoint); self.history = Array(self.history.suffix(1000)) }
                if let key = self.saveKey, let data = try? JSONEncoder().encode(self.history) {
                    UserDefaults.standard.set(data, forKey: key); self.savedHistory = self.history
                }
                PiliSleepTimer.shared.resumeManually()
                viewModel.selectPage(VideoPage(cid: checkpoint.cid, page: nil, part: checkpoint.title, duration: nil, dimension: nil))
            } catch {
                guard !Task.isCancelled, self.token == token else { return }
                self.errorMessage = error.localizedDescription
                self.choicesVisible = true
            }
        }
    }
    deinit { task?.cancel() }
}
