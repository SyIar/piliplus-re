import AVFoundation
import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

nonisolated enum PiliMediaCapture {
    /// Encodes one frame at a time. The GIF budget bounds both frame count and decoded pixels.
    @concurrent static func export(url: URL, start: Double, length: Double?, maximumSize: Int = 640,
        progress: @escaping @Sendable (Double) async -> Void = { _ in }) async throws -> URL {
        guard start.isFinite, start >= 0, length == nil || (length!.isFinite && (0.2...10).contains(length!)) else {
            throw PiliOfflineError.message("截取时间无效")
        }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": ["Referer": "https://www.bilibili.com/", "User-Agent": BiliAppSigner.Profile.androidHD.userAgent]])
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > start else { throw PiliOfflineError.message("截取位置超出视频时长") }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let edge = length == nil ? 3840 : min(max(maximumSize, 320), 960)
        generator.maximumSize = CGSize(width: edge, height: edge)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.04, preferredTimescale: 600)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PiliCapture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent(length == nil ? "frame.png" : "clip.gif")
        do {
            return try await withTaskCancellationHandler {
                let first = try await generator.image(at: CMTime(seconds: start, preferredTimescale: 600)).image
                try Task.checkCancellation()
                let span = min(length ?? 0, duration - start)
                let pixels = max(1, first.width * first.height)
                let frames = length == nil ? 1 : max(2, min(100, Int(ceil(span * 10)), 24_000_000 / pixels))
                let type = length == nil ? UTType.png.identifier : UTType.gif.identifier
                guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type as CFString, frames, nil) else {
                    throw PiliOfflineError.message("无法创建导出文件")
                }
                if length != nil { CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary) }
                let delay = span / Double(frames)
                let properties: CFDictionary? = length == nil ? nil : [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary
                CGImageDestinationAddImage(destination, first, properties)
                await progress(1 / Double(frames))
                if frames > 1 {
                    for index in 1..<frames {
                        try Task.checkCancellation()
                        let frame = try await generator.image(at: CMTime(seconds: start + Double(index) * delay, preferredTimescale: 600)).image
                        autoreleasepool { CGImageDestinationAddImage(destination, frame, properties) }
                        await progress(Double(index + 1) / Double(frames))
                    }
                }
                try Task.checkCancellation()
                guard CGImageDestinationFinalize(destination) else { throw PiliOfflineError.message("图片编码失败") }
                return output
            } onCancel: { generator.cancelAllCGImageGeneration() }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func remove(_ url: URL?) {
        guard let url, url.deletingLastPathComponent().lastPathComponent.hasPrefix("PiliCapture-") else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    static func saveImage(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw PiliOfflineError.message("请在系统设置中允许添加照片") }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
        }
    }
}
