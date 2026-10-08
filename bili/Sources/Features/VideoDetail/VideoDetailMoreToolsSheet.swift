import SwiftUI
import ChunUI

struct VideoDetailMoreToolsSheet: View {
    let viewModel: VideoDetailViewModel
    let interactionStore: VideoDetailInteractionRenderStore
    let descriptionStore: VideoDetailDescriptionRenderStore
    var onShare: () -> Void = {}
    var onDiagnostics: (() -> Void)? = nil
    @PiliDismiss private var dismiss

    var body: some View {
        NavigationStack {
            PiliForm {
                Section("\u{5e38}\u{7528}\u{64cd}\u{4f5c}") {
                    if !viewModel.detail.isPGCEpisode {
                        PiliVideoLibraryActions(viewModel: viewModel, descriptionStore: descriptionStore)
                    }
                    if let url = descriptionStore.shareURL {
                        PiliShareMenu(url: url, title: descriptionStore.shareSubject, message: descriptionStore.shareMessage) {
                            PiliLabel("\u{5206}\u{4eab}\u{89c6}\u{9891}", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .simultaneousGesture(TapGesture().onEnded { _ in onShare() })
                    }
                    if let onDiagnostics {
                        tool("\u{64ad}\u{653e}\u{8bca}\u{65ad}", icon: "stethoscope", action: onDiagnostics)
                    }
                }
                if !viewModel.detail.piliIsCourse || viewModel.detail.piliUGCSeason != nil {
                    Section("\u{4e92}\u{52a8}\u{4e0e}\u{6536}\u{85cf}") {
                        if !viewModel.detail.piliIsCourse {
                            PiliTripleButton(viewModel: viewModel, store: interactionStore, grouped: true)
                                .frame(minHeight: 44)
                        }
                        if let seasonID = viewModel.detail.piliUGCSeason?.id {
                            PiliSeasonActionsView(api: viewModel.api, seasonID: seasonID, collectionBVID: viewModel.detail.bvid)
                        }
                    }
                }
                Section("\u{89c6}\u{9891}\u{5de5}\u{5177}") {
                    tool("\u{7ae0}\u{8282}\u{4e0e}\u{89c6}\u{9891}\u{4fe1}\u{606f}", icon: "list.bullet.rectangle") {
                        PiliPresentation.present(.sheet) { PiliVideoToolsView(model: viewModel, store: viewModel.piliVideoTools) }
                    }
                    if !viewModel.detail.isPGCEpisode, !viewModel.detail.piliIsCourse {
                        tool("AI \u{603b}\u{7ed3}", icon: "text.badge.star") {
                            PiliPresentation.present(.sheet) { PiliAIConclusionView(model: viewModel) }
                        }
                        tool("\u{89c6}\u{9891}\u{70b9}\u{8e29}", icon: "hand.thumbsdown") {
                            let video = viewModel.detail
                            PiliPresentation.present(.sheet) {
                                PiliRecommendationFeedbackView(api: viewModel.api, video: video) {
                                    guard viewModel.detail.bvid == video.bvid else { return }
                                    viewModel.interactionState.isLiked = false
                                }
                            }
                        }
                    }
                    tool("\u{622a}\u{56fe}\u{4e0e}\u{52a8}\u{56fe}", icon: "camera") { PiliMediaCaptureView.present(viewModel) }
                    tool("\u{539f}\u{58f0}\u{7ffb}\u{8bd1}", icon: "waveform") {
                        PiliPresentation.present(.sheet) { NavigationStack { PiliAudioLanguageView(viewModel: viewModel) } }
                    }
                    tool("\u{79bb}\u{7ebf}\u{4e0b}\u{8f7d}", icon: "arrow.down.circle") {
                        PiliPresentation.present(.sheet) { PiliDownloadSheet(viewModel: viewModel) }
                    }
                    tool("\u{6295}\u{5c4f}", icon: "tv") {
                        PiliPresentation.present(.sheet) { PiliDLNAView(source: { try .online(viewModel) }) }
                    }
                    tool("\u{7a7a}\u{964d}\u{52a9}\u{624b}", icon: "forward.end") {
                        PiliPresentation.present(.sheet) { PiliSponsorView(model: viewModel) }
                    }
                    tool("\u{5b57}\u{5e55}", icon: "captions.bubble") {
                        PiliSubtitleSettingsView.present(controller: viewModel.piliSubtitles) { seconds in
                            guard let player = viewModel.stablePlayerViewModel else { return }
                            player.seek(by: seconds - player.currentTime)
                        }
                    }
                    if viewModel.piliPlaybackQueue != nil || viewModel.detail.piliUGCSeason != nil {
                        tool("\u{64ad}\u{653e}\u{5217}\u{8868}", icon: "list.bullet") {
                            PiliPresentation.present(.sheet) { PiliCollectionQueueView(viewModel: viewModel) }
                        }
                    }
                    tool("\u{4e92}\u{52a8}\u{5206}\u{652f}", icon: "point.topleft.down.to.point.bottomright.curvepath") {
                        PiliPresentation.present(.sheet) { PiliInteractiveHistoryView(controller: viewModel.piliInteractive) }
                    }
                    if let aid = viewModel.detail.aid {
                        tool("\u{8bb0}\u{7b14}\u{8bb0}", icon: "square.and.pencil") {
                            PiliPresentation.present(.sheet) {
                                NavigationStack {
                                    PiliNoteEditorView(api: viewModel.api, aid: aid, initialTitle: viewModel.detail.title,
                                                       noteID: nil, initialText: "", time: viewModel.stablePlayerViewModel?.currentTime)
                                }
                            }
                        }
                        tool("\u{4e3e}\u{62a5}\u{89c6}\u{9891}", icon: "exclamationmark.bubble") {
                            PiliPresentation.present(.sheet) {
                                NavigationStack { PiliAccountWebView(api: viewModel.api, url: URL(string: "https://www.bilibili.com/appeal/?avid=\(aid)")!, title: "\u{4e3e}\u{62a5}\u{89c6}\u{9891}") }
                            }
                        }
                        tool("\u{89c6}\u{9891}\u{7b14}\u{8bb0}", icon: "note.text") {
                            PiliPresentation.present(.sheet) { PiliNotesLibraryView(api: viewModel.api, video: viewModel.detail) }
                        }
                    }
                }
            }
            .navigationTitle("\u{66f4}\u{591a}\u{64cd}\u{4f5c}")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("\u{5b8c}\u{6210}") { dismiss() }
                        .accessibilityIdentifier("video.tools.close")
                }
            }
        }
        .piliPresentationDetents([.large])
    }

    private func tool(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PiliLabel(title, systemImage: icon)
                .font(.body)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

}
