import SwiftUI

struct PiliRecommendationFeedbackView: View {
    let api: BiliAPIClient
    let video: VideoItem
    let onDislike: (() -> Void)?
    private let identity: PiliAccountIdentity
    @State private var busy = false
    @State private var error: String?
    @State private var disliked: Bool?
    @State private var submitted = false
    @Environment(\.dismiss) private var dismiss
    init(api: BiliAPIClient, video: VideoItem, onDislike: (() -> Void)? = nil) {
        self.api = api; self.video = video; self.onDislike = onDislike
        identity = PiliAccountIdentity(api.requestSnapshot())
    }
    var body: some View {
        NavigationStack {
            List {
                Text(video.title).font(.headline)
                if submitted { Label("已提交推荐反馈", systemImage: "checkmark.circle") }
                else if let metadata = video.piliRecommendation, !metadata.reasons.isEmpty {
                    Section("不感兴趣的原因") {
                        ForEach(metadata.reasons) { reason in
                            Button(reason.name) { submit(reason) }.disabled(busy)
                        }
                    }
                } else { Text("当前卡片未提供推荐反馈原因，可使用视频点踩。") }
                if let disliked {
                    Button(disliked ? "取消视频点踩" : "视频点踩", systemImage: "hand.thumbsdown") { dislike(!disliked) }.disabled(busy)
                }
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.secondary) }
            }
            .navigationTitle("推荐与视频反馈").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task {
                guard let aid = video.aid, aid > 0 else { return }
                do { disliked = try await api.piliVideoDisliked(aid: aid, identity: identity) }
                catch { self.error = error.localizedDescription }
            }
        }
    }
    private func submit(_ reason: PiliFeedFeedbackReason) {
        guard !busy else { return }; busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                try await api.piliFeedFeedback(video: video, reason: reason, identity: identity)
                guard identity.matches(api.requestSnapshot()) else { return }
                PiliFeedDismissals.shared.dismiss(video, account: identity.mid); submitted = true
            } catch { self.error = error.localizedDescription }
        }
    }
    private func dislike(_ value: Bool) {
        guard !busy, let aid = video.aid else { return }; busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                try await api.piliDislikeVideo(aid: aid, dislike: value, identity: identity)
                disliked = value
                if value { onDislike?() }
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct PiliRecommendationMenu: ViewModifier {
    let video: VideoItem
    @EnvironmentObject private var dependencies: AppDependencies
    func body(content: Content) -> some View {
        content.contextMenu {
            Button("不感兴趣／视频点踩", systemImage: "hand.thumbsdown") {
                AppHelper.shared.presentSheet(.sheet) { PiliRecommendationFeedbackView(api: dependencies.api, video: video) }
            }
        }
    }
}
