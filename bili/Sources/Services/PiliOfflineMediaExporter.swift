import AVFoundation
import Foundation
import PiliPlaybackCore

@MainActor
enum PiliOfflineMediaExporter {
    static func finalize(_ item: OfflineDownloadItem) async throws -> URL {
        if item.effectiveMediaKind == .audio { return try await finalizeAudio(item) }
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
            try await validateOutput(output, expectsVideo: true, expectsAudio: item.requiresAudio || !audioTracks.isEmpty)
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    private static func finalizeAudio(_ item: OfflineDownloadItem) async throws -> URL {
        let source = AVURLAsset(url: try PiliOfflineStorage.part(item.id, .audio))
        let duration = try await source.load(.duration)
        let tracks = try await source.loadTracks(withMediaType: .audio)
        guard duration.isNumeric, duration.seconds > 0, !tracks.isEmpty else {
            throw PiliOfflineError.message("下载文件没有有效的音频轨道")
        }
        let composition = AVMutableComposition()
        for track in tracks {
            guard let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw PiliOfflineError.message("无法创建音频轨道")
            }
            try destination.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
        }
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw PiliOfflineError.message("无法创建音频导出任务")
        }
        let type: AVFileType = exporter.supportedFileTypes.contains(.m4a) ? .m4a : .mov
        guard exporter.supportedFileTypes.contains(type) else { throw PiliOfflineError.message("此音频格式暂不支持无损封装") }
        let output = try PiliOfflineStorage.directory(item.id).appendingPathComponent(type == .m4a ? "media.m4a" : "media.mov")
        try? FileManager.default.removeItem(at: output)
        do {
            try await exporter.export(to: output, as: type)
            try Task.checkCancellation()
            try await validateOutput(output, expectsVideo: false, expectsAudio: true)
            return output
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    private static func validateOutput(_ url: URL, expectsVideo: Bool, expectsAudio: Bool) async throws {
        guard PiliOfflineStorage.size(url) > 0 else { throw PiliOfflineError.message("导出的文件为空") }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard try await asset.load(.isPlayable), duration.isNumeric, duration.seconds > 0 else {
            throw PiliOfflineError.message("导出的文件无法完整播放")
        }
        if expectsVideo, try await asset.loadTracks(withMediaType: .video).isEmpty {
            throw PiliOfflineError.message("导出的文件缺少视频轨道")
        }
        if expectsAudio, try await asset.loadTracks(withMediaType: .audio).isEmpty {
            throw PiliOfflineError.message("导出的文件缺少音频轨道")
        }
    }
}
