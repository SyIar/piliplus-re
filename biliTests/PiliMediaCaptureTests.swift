import AVFoundation
import ImageIO
import Photos
import UIKit
import XCTest
@testable import bili

@MainActor
final class PiliMediaCaptureTests: XCTestCase {
    func testRealMovieProducesPNGAndTimedGIF() async throws {
        let movie = try await PiliTestMovie.make()
        defer { try? FileManager.default.removeItem(at: movie.deletingLastPathComponent()) }
        let png = try await PiliMediaCapture.export(url: movie, start: 0.2, length: nil)
        defer { PiliMediaCapture.remove(png) }
        let image = try XCTUnwrap(CGImageSourceCreateWithURL(png as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(image) as String?, "public.png")
        XCTAssertEqual(CGImageSourceGetCount(image), 1)
        let gif = try await PiliMediaCapture.export(url: movie, start: 0.2, length: 1)
        defer { PiliMediaCapture.remove(gif) }
        let animation = try XCTUnwrap(CGImageSourceCreateWithURL(gif as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(animation), 10)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(animation, 0, nil) as? [String: Any])
        let timing = try XCTUnwrap(properties[kCGImagePropertyGIFDictionary as String] as? [String: Any])
        XCTAssertEqual(timing[kCGImagePropertyGIFDelayTime as String] as? Double ?? 0, 0.1, accuracy: 0.001)
    }

    func testLivePhotoPairHasMatchingIdentifiersAndTimedMetadata() async throws {
        let movie = try await PiliTestMovie.make()
        defer { try? FileManager.default.removeItem(at: movie.deletingLastPathComponent()) }
        let png = try await PiliMediaCapture.export(url: movie, start: 0, length: nil)
        defer { PiliMediaCapture.remove(png) }
        let pair = try await PiliLivePhotoEncoder.pair(image: png, video: movie)
        let image = try XCTUnwrap(CGImageSourceCreateWithURL(pair.image as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [String: Any])
        let maker = try XCTUnwrap(properties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any])
        let id = try XCTUnwrap(maker["17"] as? String)
        let asset = AVURLAsset(url: pair.video)
        let metadata = try await asset.load(.metadata)
        let identity = try XCTUnwrap(metadata.first { ($0.key as? String) == "com.apple.quicktime.content.identifier" })
        let movieID = try await identity.load(.stringValue)
        XCTAssertEqual(movieID, id)
        let tracks = try await asset.loadTracks(withMediaType: .metadata)
        XCTAssertEqual(tracks.count, 1)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: tracks[0], outputSettings: nil)
        let adaptor = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: output)
        reader.add(output); XCTAssertTrue(reader.startReading())
        let group = try XCTUnwrap(adaptor.nextTimedMetadataGroup())
        XCTAssertTrue(group.items.contains { ($0.key as? String) == "com.apple.quicktime.still-image-time" })
        reader.cancelReading()
        let live: PHLivePhoto? = await withCheckedContinuation { continuation in
            PHLivePhoto.request(withResourceFileURLs: [pair.image, pair.video], placeholderImage: nil,
                targetSize: CGSize(width: 160, height: 90), contentMode: .aspectFit) { photo, info in
                if (info[PHLivePhotoInfoIsDegradedKey] as? Bool) != true { continuation.resume(returning: photo) }
            }
        }
        XCTAssertNotNil(live, "Photos must recognize the generated resources as one Live Photo")
    }

    func testExportRejectsInvalidRangeBeforeCreatingFiles() async {
        do { _ = try await PiliMediaCapture.export(url: URL(fileURLWithPath: "/missing.mp4"), start: .nan, length: 10); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("时间")) }
    }
}

@MainActor
enum PiliTestMovie {
    static func make() async throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PiliTestMovie-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("test.mov")
        let writer = try AVAssetWriter(outputURL: file, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 160, AVVideoHeightKey: 96])
        let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 96,
            kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        writer.add(input); XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        for index in 0..<30 {
            while !input.isReadyForMoreMediaData {
                guard ContinuousClock.now < deadline else { writer.cancelWriting(); throw URLError(.timedOut) }
                try await Task.sleep(for: .milliseconds(5))
            }
            var buffer: CVPixelBuffer?
            let pool = try XCTUnwrap(adaptor.pixelBufferPool)
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer), kCVReturnSuccess)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            if let base = CVPixelBufferGetBaseAddress(pixels) { memset(base, Int32(index * 7), CVPixelBufferGetDataSize(pixels)) }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(index), timescale: 10)))
        }
        input.markAsFinished(); await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return file
    }
}
