import SwiftUI

struct PiliCollectionDownloadView: View {
    let api: BiliAPIClient
    let seed: VideoItem
    @State private var videos: [VideoItem] = []
    @State private var selected = Set<String>()
    @State private var loading = true
    @State private var error: String?
    @State private var request: PiliBatchDownloadRequest?
    @State private var loadID = UUID()
    var body: some View {
        List {
            if loading { ProgressView("读取全部分集") }
            if let error { Text(error); Button("重试") { loadID = UUID() } }
            if !videos.isEmpty {
                Button(selected.count == videos.count ? "取消全选" : "全选") { selected = selected.count == videos.count ? [] : Set(videos.map(key)) }
                ForEach(videos, id: \.bvid) { video in
                    Toggle(video.title, isOn: Binding(get: { selected.contains(key(video)) }, set: { value in
                        if value { selected.insert(key(video)) } else { selected.remove(key(video)) }
                    }))
                }
                Button("下载所选 \(selected.count) 集") {
                    request = .init(source: .selected(videos.filter { selected.contains(key($0)) }), title: seed.piliUGCSeason?.title ?? seed.title,
                        purpose: .playback, credentialVersion: api.requestSnapshot(purpose: .playback).playbackCredentialVersion)
                }.disabled(selected.isEmpty)
            }
        }.navigationTitle("缓存合集与分集")
            .task(id: loadID) {
                loading = true; error = nil; defer { loading = false }
                do {
                    let values: [VideoItem]
                    if seed.isPGCEpisode {
                        let season = try await api.fetchPgcSeasonInfo(seasonID: seed.pgcSeasonID, epID: seed.pgcEpisodeID, isCourse: seed.piliIsCourse)
                        values = season.allPlayableEpisodes.compactMap { $0.videoItem(in: season) }
                    } else { values = seed.piliUGCSeason?.videos(defaultOwner: seed.owner) ?? [seed] }
                    try Task.checkCancellation()
                    videos = values; selected = Set(values.map(key))
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
            .sheet(item: $request) { request in PiliBatchDownloadSheet(api: api, request: request) }
    }
    private func key(_ video: VideoItem) -> String { "\(video.bvid)|\(video.pgcEpisodeID ?? 0)" }
}
