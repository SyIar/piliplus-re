import Combine
import SwiftUI
import ChunUI

@MainActor
final class LiveCDNProbeModel: ObservableObject {
    struct Row: Identifiable {
        let id: URL
        let title: String
        var progress: LiveCDNProbeProgress?
        var error: String?
    }
    @Published private(set) var rows: [Row] = []
    @Published private(set) var isRunning = false
    @Published private(set) var completed = 0
    @Published private(set) var message: String?
    private let service: LiveCDNProbeService
    private var task: Task<Void, Never>?
    private var generation = UUID()
    init(service: LiveCDNProbeService = LiveCDNProbeService()) { self.service = service }

    func start(candidates: [LiveStreamURLCandidate], headers: [String: String]) {
        cancel()
        var seen = Set<URL>()
        let unique = candidates.filter { seen.insert($0.url).inserted }
        rows = Array(unique.prefix(12)).enumerated().map { index, candidate in
            Row(id: candidate.url, title: "线路 \(index + 1) · \(candidate.url.host ?? "CDN")")
        }
        completed = 0
        guard !rows.isEmpty else { message = "暂无可测速的直播线路"; return }
        message = unique.count > rows.count ? "采样前 12 条线路，每条最多 256 KB" : "每条最多采样 256 KB；结果受直播分片和当前网络影响"
        isRunning = true
        let token = generation
        let urls = rows.map(\.id)
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.isRunning = false; self.task = nil } }
            for url in urls {
                guard !Task.isCancelled, self.generation == token else { return }
                do {
                    _ = try await self.service.probe(url: url, headers: headers) { [weak self] progress in
                        await self?.apply(progress, url: url, token: token)
                    }
                } catch {
                    guard !Task.isCancelled, self.generation == token else { return }
                    if let index = self.rows.firstIndex(where: { $0.id == url }) { self.rows[index].error = error.localizedDescription }
                }
                guard self.generation == token, !Task.isCancelled else { return }
                self.completed += 1
            }
        }
    }
    private func apply(_ progress: LiveCDNProbeProgress, url: URL, token: UUID) {
        guard generation == token, !Task.isCancelled, let index = rows.firstIndex(where: { $0.id == url }) else { return }
        rows[index].progress = progress
    }
    func cancel() {
        generation = UUID(); task?.cancel(); task = nil
        if isRunning { message = "测速已取消，已完成的结果保留；播放线路未改变" }
        isRunning = false
    }
    func waitUntilFinished() async { await task?.value }
    deinit { task?.cancel() }
}

struct LiveCDNProbeSection: View {
    @ObservedObject var viewModel: LiveRoomViewModel
    @StateObject private var model = LiveCDNProbeModel()
    var body: some View {
        Section("直播线路测速") {
            if model.isRunning {
                ProgressView("已完成 \(model.completed)/\(model.rows.count)", value: Double(model.completed), total: Double(model.rows.count))
                Button("取消测速", role: .cancel) { model.cancel() }
            } else {
                Button(model.rows.isEmpty ? "开始测速" : "重新测速") {
                    model.start(candidates: viewModel.streamCandidates, headers: viewModel.streamHTTPHeaders)
                }.disabled(viewModel.streamCandidates.isEmpty)
            }
            if let message = model.message { Text(message).piliFont(.sm).foregroundStyle(.secondary) }
            ForEach(model.rows) { row in
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.title).piliFont(.base)
                    if let error = row.error { Text(error).piliFont(.sm).foregroundStyle(.secondary) }
                    else if let progress = row.progress {
                        Text("\(progress.phase) · \(ByteCountFormatter.string(fromByteCount: Int64(progress.bytes), countStyle: .binary)) · \(Int(progress.bytesPerSecond / 1024)) KB/s").piliFont(.sm).monospacedDigit()
                        if progress.phase == "完成", !model.isRunning {
                            Button("使用此线路") {
                                if let index = viewModel.streamCandidates.firstIndex(where: { $0.url == row.id }) {
                                    viewModel.selectStreamCandidate(id: index)
                                }
                            }
                        }
                    } else { Text("等待测速").piliFont(.sm).foregroundStyle(.secondary) }
                }
            }
        }
        .onDisappear { model.cancel() }
        .onChange(of: viewModel.streamCandidates) { _, _ in model.cancel() }
    }
}
