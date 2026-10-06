import SwiftUI
import ChunUI

extension VideoDetailViewModel {
    func resetPiliAudioLanguage() {
        piliAudioLanguageGeneration = UUID(); piliAudioLanguage = nil; piliAudioLanguages = []
        piliAudioLanguageBusy = false; piliAudioLanguageError = nil
    }
    func selectPiliAudioLanguage(_ language: String?) async {
        guard let cid = selectedCID, !piliAudioLanguageBusy, !isSwitchingPlayQuality,
              !isPlaybackInvalidatedForNavigation else { return }
        guard language == nil || piliAudioLanguages.contains(where: { $0.id == language }) else { return }
        let bvid = detail.bvid, generation = UUID()
        piliAudioLanguageGeneration = generation; piliAudioLanguageBusy = true; piliAudioLanguageError = nil
        defer { if piliAudioLanguageGeneration == generation { piliAudioLanguageBusy = false } }
        do {
            let data = try await api.piliLanguagePlayURL(bvid: bvid, cid: cid, language: language ?? "",
                quality: selectedPlayVariant?.quality ?? 80, seasonID: detail.pgcSeasonID, episodeID: detail.pgcEpisodeID)
            guard !Task.isCancelled, piliAudioLanguageGeneration == generation, !isPlaybackInvalidatedForNavigation,
                  detail.bvid == bvid, selectedCID == cid else { return }
            let variants = sortedPlayVariants(playVariants(from: data))
            guard let variant = variants.first(where: { $0.isPlayable && $0.quality == selectedPlayVariant?.quality })
                    ?? variants.first(where: \.isPlayable) else { throw BiliAPIError.emptyPlayURL }
            cancelStartupPlayURLTask(); cancelBufferingCDNRefreshTask(); cancelPlaybackRecoveryReloadTask()
            piliAudioLanguage = language
            currentPlayURLData = data; playVariants = variants; applyVideoListenAudioVariants(from: data)
            selectPlayVariant(variant)
            if let subtitle = piliAudioLanguages.first(where: { $0.id == language })?.subtitleLang,
               let track = piliSubtitles.tracks.first(where: { $0.lan == subtitle }) { piliSubtitles.select(track.id) }
        } catch {
            if !Task.isCancelled, piliAudioLanguageGeneration == generation { piliAudioLanguageError = error.localizedDescription }
        }
    }
}

struct PiliAudioLanguageView: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    @State private var task: Task<Void, Never>?
    var body: some View {
        PiliList {
            Section {
                choice("原声", language: nil)
                ForEach(viewModel.piliAudioLanguages) { language in choice(language.displayTitle, language: language.id) }
            }.disabled(viewModel.piliAudioLanguageBusy || viewModel.isSwitchingPlayQuality)
            if viewModel.piliAudioLanguageBusy || viewModel.isSwitchingPlayQuality { ProgressView("正在切换音轨") }
            if let message = viewModel.piliAudioLanguageError { Text(message).foregroundStyle(.secondary) }
            Text("仅显示当前视频提供的语言。切换会保留播放位置和倍速，需要登录播放账号。").font(.cc.sm).foregroundStyle(.secondary)
        }.navigationTitle("原声翻译").onDisappear { task?.cancel() }
    }
    private func choice(_ title: String, language: String?) -> some View {
        Button {
            task?.cancel(); task = Task { await viewModel.selectPiliAudioLanguage(language) }
        } label: {
            HStack { Text(title); Spacer(); if viewModel.piliAudioLanguage == language { PiliIcon(systemName: "checkmark") } }
        }
    }
}
