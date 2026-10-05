import AVFoundation
import Foundation
import PiliPlaybackCore

@MainActor
enum PiliOfflineMediaExporter {
    static func finalize(_ item: OfflineDownloadItem) async throws -> URL {
        let videoURL = try PiliOfflineStorage.part(item.id, .video)
        let videoAsset = AVURLAsset(url: videoURL)
        guard try await videoAsset.load(.isPlayable) else { throw PiliOfflineError.message("下载的视频格式无法由 AVPlayer 播放") }
        let videoDuration = try await videoAsset.load(.duration)
        guard videoDuration.isNumeric, videoDuration.seconds > 0 else { throw PiliOfflineError.message("下载文件的时长无效") }
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { throw PiliOfflineError.message("下载文件没有视频轨道") }

        let composition = AVMutableComposition()
        for track in videoTracks {
            guard let destination = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try destination.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: track, at: .zero)
            destination.preferredTransform = try await track.load(.preferredTransform)
        }
        let audioAsset = item.requiresAudio ? AVURLAsset(url: try PiliOfflineStorage.part(item.id, .audio)) : videoAsset
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        if item.requiresAudio && audioTracks.isEmpty { throw PiliOfflineError.message("下载文件没有音频轨道") }
        let audioDuration = try await audioAsset.load(.duration)
        for track in audioTracks {
            guard let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try destination.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(videoDuration, audioDuration)), of: track, at: .zero)
        }
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw PiliOfflineError.message("无法创建音视频合并任务")
        }
        let fileType: AVFileType = exporter.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        let output = try PiliOfflineStorage.directory(item.id).appendingPathComponent(fileType == .mp4 ? "media.mp4" : "media.mov")
        try? FileManager.default.removeItem(at: output)
        do {
            try await exporter.export(to: output, as: fileType)
            try Task.checkCancellation()
            guard PiliOfflineStorage.size(output) > 0 else { throw PiliOfflineError.message("合并后的文件为空") }
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}
