import Foundation
import SwiftUI

nonisolated struct PiliAIConclusion: Equatable, Sendable {
    struct Point: Identifiable, Equatable, Sendable { let id: Int; let seconds: Double; let content: String }
    struct Outline: Identifiable, Equatable, Sendable { let id: Int; let title: String; let points: [Point] }
    let summary: String
    let outline: [Outline]
    init(_ data: DynamicJSONValue) throws {
        guard data["code"].piliInt == 0 else {
            let message = data["message"].piliString
            throw PiliOfflineError.message(message.isEmpty ? "此视频暂未提供 AI 总结（\(data["code"].piliInt)）" : message)
        }
        let result = data["model_result"]
        summary = result["summary"].piliString
        outline = result["outline"].piliArray.prefix(200).enumerated().map { index, value in
            let points = value["part_outline"].piliArray.prefix(500).enumerated().compactMap { offset, point -> Point? in
                guard let seconds = Double(point["timestamp"].piliString), seconds.isFinite, seconds >= 0, seconds <= Double(Int32.max),
                      !point["content"].piliString.isEmpty else { return nil }
                return .init(id: offset, seconds: seconds, content: point["content"].piliString)
            }
            return Outline(id: index, title: value["title"].piliString, points: points)
        }
    }
    var isEmpty: Bool { summary.isEmpty && outline.allSatisfy { $0.points.isEmpty } }
}

extension BiliAPIClient {
    func piliAIConclusion(video: VideoItem, cid: Int, identity: PiliAccountIdentity?) async throws -> PiliAIConclusion {
        guard !video.bvid.isEmpty, cid > 0 else { throw BiliAPIError.missingPayload }
        var query = ["bvid": video.bvid, "cid": String(cid)]
        if let mid = video.owner?.mid, mid > 0 { query["up_mid"] = String(mid) }
        return try await PiliAIConclusion(piliContentRead("/x/web-interface/view/conclusion/get", query: query, signed: true, identity: identity))
    }
}

struct PiliAIConclusionView: View {
    @ObservedObject var model: VideoDetailViewModel
    @ObservedObject private var session: SessionStore
    @State private var result: PiliAIConclusion?
    @State private var resultKey: String?
    @State private var loading = false
    @State private var error: String?
    @State private var generation = UUID()
    @State private var retry = 0
    @Environment(\.dismiss) private var dismiss
    init(model: VideoDetailViewModel) { self.model = model; _session = ObservedObject(wrappedValue: model.api.sessionStore) }
    private var key: String { "\(model.detail.bvid):\(model.selectedCID ?? 0):\(session.playbackCredentialVersion):\(retry)" }
    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView("加载 AI 总结") }
                if let error { Text(error); Button("重试") { retry += 1 } }
                if let result {
                    if result.isEmpty { ContentUnavailableView("暂无 AI 总结", systemImage: "text.badge.star", description: Text("平台尚未为当前分 P 提供总结")) }
                    if !result.summary.isEmpty { Section("视频总结") { Text(result.summary).textSelection(.enabled) } }
                    ForEach(result.outline) { outline in
                        Section(outline.title) {
                            ForEach(outline.points) { point in
                                Button {
                                    guard resultKey == key, let player = model.stablePlayerViewModel, !player.isTerminated else { return }
                                    player.seek(by: point.seconds - player.currentTime); dismiss()
                                } label: {
                                    HStack(alignment: .top) {
                                        Text(BiliFormatters.duration(Int(point.seconds))).monospacedDigit().foregroundStyle(.tint)
                                        Text(point.content).foregroundStyle(.primary)
                                    }
                                }.disabled(model.stablePlayerViewModel == nil || resultKey != key)
                            }
                        }
                    }
                }
            }
            .navigationTitle("AI 总结").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task(id: key) { await load() }
        }
    }
    private func load() async {
        let token = UUID(), requestKey = key; generation = token; result = nil; resultKey = nil; error = nil; loading = true
        defer { if generation == token { loading = false } }
        let video = model.detail, identity = PiliAccountIdentity(model.api.requestSnapshot())
        guard let cid = model.selectedCID else { error = "视频分 P 尚未加载"; return }
        do {
            let value = try await model.api.piliAIConclusion(video: video, cid: cid, identity: identity.mid > 0 ? identity : nil)
            guard !Task.isCancelled, generation == token, model.selectedCID == cid, model.detail.bvid == video.bvid else { return }
            resultKey = requestKey; result = value
        } catch { if !Task.isCancelled, generation == token { self.error = error.localizedDescription } }
    }
}
