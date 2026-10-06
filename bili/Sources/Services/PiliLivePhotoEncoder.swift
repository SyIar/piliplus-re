import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum PiliLivePhotoEncoder {
    struct Pair: Sendable { let image: URL; let video: URL }

    /// Photos requires the same asset identifier in MakerApple/17 and the QuickTime
    /// container, plus a timed still-image marker. A plain JPEG + MP4 is not a Live Photo.
    @concurrent static func pair(image: URL, video: URL) async throws -> Pair {
        let directory = image.deletingLastPathComponent()
        let identifier = UUID().uuidString
        let photo = directory.appendingPathComponent("live-\(identifier).jpg")
        let movie = directory.appendingPathComponent("live-\(identifier).mov")
        do {
            guard let source = CGImageSourceCreateWithURL(image as CFURL, nil),
                  let destination = CGImageDestinationCreateWithURL(photo as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw PiliOfflineError.message("无法读取实况照片")
            }
            var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
            var maker = properties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any] ?? [:]
            maker["17"] = identifier; properties[kCGImagePropertyMakerAppleDictionary as String] = maker
            properties[kCGImageDestinationLossyCompressionQuality as String] = 0.95
            CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw PiliOfflineError.message("实况照片编码失败") }
            try await writeMovie(source: video, output: movie, identifier: identifier)
            try Task.checkCancellation()
            return Pair(image: photo, video: movie)
        } catch {
            try? FileManager.default.removeItem(at: photo); try? FileManager.default.removeItem(at: movie)
            throw error
        }
    }

    private static func writeMovie(source: URL, output: URL, identifier: String) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        guard duration.isNumeric, duration.seconds > 0, duration.seconds <= 60 else {
            throw PiliOfflineError.message("实况视频时长无效")
        }
        let reader = try AVAssetReader(asset: asset), writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        var pairs: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = []
        let tracks = try await asset.loadTracks(withMediaType: .video) + asset.loadTracks(withMediaType: .audio)
        guard tracks.contains(where: { $0.mediaType == .video }) else { throw PiliOfflineError.message("实况视频没有画面") }
        for track in tracks {
            let format = try await track.load(.formatDescriptions).first
            let read = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            read.alwaysCopiesSampleData = false
            let write = AVAssetWriterInput(mediaType: track.mediaType, outputSettings: nil, sourceFormatHint: format)
            write.expectsMediaDataInRealTime = false
            if track.mediaType == .video { write.transform = try await track.load(.preferredTransform) }
            guard reader.canAdd(read), writer.canAdd(write) else { throw PiliOfflineError.message("实况视频编码不受支持") }
            reader.add(read); writer.add(write); pairs.append((read, write))
        }
        let identity = AVMutableMetadataItem()
        identity.keySpace = .quickTimeMetadata; identity.key = "com.apple.quicktime.content.identifier" as NSString
        identity.value = identifier as NSString; identity.dataType = kCMMetadataBaseDataType_UTF8 as String
        writer.metadata = [identity]
        let spec: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: kCMMetadataBaseDataType_SInt8 as String]
        var format: CMMetadataFormatDescription?
        let result = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed, metadataSpecifications: [spec] as CFArray, formatDescriptionOut: &format)
        guard result == noErr, let format else { throw PiliOfflineError.message("无法创建实况时间标记") }
        let metadata = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: format)
        let adaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadata)
        guard writer.canAdd(metadata) else { throw PiliOfflineError.message("实况时间标记不可用") }
        writer.add(metadata)
        guard reader.startReading(), writer.startWriting() else { throw writer.error ?? reader.error ?? PiliOfflineError.message("无法创建实况视频") }
        writer.startSession(atSourceTime: .zero)
        do {
            try await withTaskCancellationHandler {
                let still = AVMutableMetadataItem()
                still.keySpace = .quickTimeMetadata; still.key = "com.apple.quicktime.still-image-time" as NSString
                still.value = NSNumber(value: Int8(0)); still.dataType = kCMMetadataBaseDataType_SInt8 as String
                guard adaptor.append(AVTimedMetadataGroup(items: [still], timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 30)))) else {
                    throw writer.error ?? PiliOfflineError.message("无法写入实况时间标记")
                }
                metadata.markAsFinished()
                var ended = Set<Int>()
                while ended.count < pairs.count {
                    try Task.checkCancellation()
                    guard writer.status == .writing, reader.status == .reading || reader.status == .completed else {
                        throw writer.error ?? reader.error ?? PiliOfflineError.message("实况视频处理失败")
                    }
                    var advanced = false
                    for index in pairs.indices where !ended.contains(index) {
                        let (read, write) = pairs[index]
                        guard write.isReadyForMoreMediaData else { continue }
                        if let sample = read.copyNextSampleBuffer() {
                            guard write.append(sample) else { throw writer.error ?? PiliOfflineError.message("无法写入实况视频") }
                        } else { write.markAsFinished(); ended.insert(index) }
                        advanced = true
                    }
                    if !advanced { try await Task.sleep(for: .milliseconds(2)) }
                }
                guard reader.status != .failed else { throw reader.error ?? PiliOfflineError.message("实况视频读取失败") }
                await writer.finishWriting()
                guard writer.status == .completed else { throw writer.error ?? PiliOfflineError.message("实况视频保存失败") }
            } onCancel: { reader.cancelReading(); writer.cancelWriting() }
        } catch { reader.cancelReading(); writer.cancelWriting(); throw error }
    }
}
