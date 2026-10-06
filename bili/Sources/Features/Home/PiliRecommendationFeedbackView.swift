import SwiftUI
import UIKit
import ChunUI

struct PiliRecommendationFeedbackView: View {
    let api: BiliAPIClient
    let video: VideoItem
    let onDislike: (() -> Void)?
    private let identity: PiliAccountIdentity
    private let interactionIdentity: PiliAccountIdentity
    @State private var busy = false
    @State private var error: String?
    @State private var disliked: Bool?
    @State private var submitted = false
    @PiliDismiss private var dismiss
    init(api: BiliAPIClient, video: VideoItem, onDislike: (() -> Void)? = nil) {
        self.api = api; self.video = video; self.onDislike = onDislike
        identity = PiliAccountIdentity(api.requestSnapshot())
        interactionIdentity = PiliAccountIdentity(api.requestSnapshot(purpose: .interaction))
    }
    var body: some View {
        NavigationStack {
            PiliList {
                Text(video.title).piliFont(.baseBold)
                if submitted { PiliLabel("已提交推荐反馈", systemImage: "checkmark.circle") }
                else if let metadata = video.piliRecommendation, !metadata.reasons.isEmpty {
                    Section("不感兴趣的原因") {
                        ForEach(metadata.reasons) { reason in
                            Button(reason.name) { submit(reason) }.disabled(busy)
                        }
                    }
                } else { Text("当前卡片未提供推荐反馈原因，可使用视频点踩。") }
                if let disliked {
                    PiliIconButton(disliked ? "取消视频点踩" : "视频点踩", systemImage: "hand.thumbsdown") { dislike(!disliked) }.disabled(busy)
                }
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.secondary) }
            }
            .navigationTitle("推荐与视频反馈").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task {
                guard let aid = video.aid, aid > 0 else { return }
                do { disliked = try await api.piliVideoDisliked(aid: aid, identity: interactionIdentity) }
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
                try await api.piliDislikeVideo(aid: aid, dislike: value, identity: interactionIdentity)
                guard interactionIdentity.matches(api.requestSnapshot(purpose: .interaction)) else { return }
                disliked = value
                if value { onDislike?() }
            } catch { self.error = error.localizedDescription }
        }
    }
}

/// Shared by the visible overflow button and the card's long-press menu.
struct PiliRecommendationActions: View {
    let video: VideoItem
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var session: SessionStore
    @Environment(\.openVideoOwnerRouteAction) private var openOwner
    @State private var addingToWatchLater = false

    // UIKit-backed menus require native Text/Label action titles. The masked
    // Pika label is for SwiftUI page controls; wrapping it here loses the title
    // when SwiftUI converts the actions to UIMenu (including accessibility).
    var body: some View {
        if session.isLoggedIn {
            Button("稍后再看") {
                guard !addingToWatchLater else { return }
                addingToWatchLater = true
                Task {
                    defer { addingToWatchLater = false }
                    do {
                        try await dependencies.api.addToWatchLater(bvid: video.bvid)
                        CCToastCenter.shared.show(.success, "已加入稍后再看")
                    } catch { CCToastCenter.shared.show(.error, error.localizedDescription) }
                }
            }.disabled(addingToWatchLater)
        }
        if let owner = video.owner, owner.mid > 0 {
            if let openOwner { Button("访问 UP 主") { openOwner(owner) } }
            else { NavigationLink("访问 UP 主", value: owner) }
        }
        Button("复制 BV 号") {
            UIPasteboard.general.string = video.bvid
            CCToastCenter.shared.show(.success, "已复制 BV 号")
        }
        Button("复制链接") {
            UIPasteboard.general.string = "https://www.bilibili.com/video/\(video.bvid)"
            CCToastCenter.shared.show(.success, "已复制链接")
        }
        Divider()
        Button("不感兴趣") {
            PiliPresentation.present(.sheet) {
                PiliRecommendationFeedbackView(api: dependencies.api, video: video)
            }
        }
    }
}
