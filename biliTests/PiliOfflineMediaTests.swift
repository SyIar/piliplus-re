import AVFoundation
import PiliPlaybackCore
import XCTest
@testable import bili

@MainActor
final class PiliOfflineMediaTests: H264PlaybackTestCase {
    func testAudioSelectionReturnsOnlyAudioURLAndRejectsUnavailableQuality() throws {
        let data = try playData()
        var item = record()
        item.mediaKind = .audio
        item.audioQualityID = 30280
        item.codec = "mp4a.40.2"
        let selection = try PiliOfflineMediaSelection.resolve(item: item, data: data)
        XCTAssertEqual(Set(selection.urls.keys), [.audio])
        XCTAssertEqual(selection.urls[.audio]?.lastPathComponent, "audio.m4s")
        item.audioQualityID = 30251
        XCTAssertThrowsError(try PiliOfflineMediaSelection.resolve(item: item, data: data))
    }

    func testBatchQualityDoesNotExceedCapAndPagesKeepOrderWithoutDuplicateCID() throws {
        let data = try playData()
        XCTAssertEqual(PiliBatchDownloadPlanner.variant(in: data, maximumQuality: 80)?.quality, 80)
        XCTAssertNil(PiliBatchDownloadPlanner.variant(in: data, maximumQuality: 16))
        let video = try JSONDecoder().decode(VideoItem.self, from: Data(#"{"bvid":"BVbatch","title":"合集","pages":[{"cid":11,"page":1},{"cid":11,"page":2},{"cid":22,"page":3},{"cid":0,"page":4}]}"#.utf8))
        XCTAssertEqual(PiliBatchDownloadPlanner.pages(for: video, allParts: true).map(\.cid), [11, 22])
        XCTAssertEqual(PiliBatchDownloadPlanner.pages(for: video, allParts: false).map(\.cid), [11])
    }

    func testAudioExportCreatesPlayableFileWithoutVideoAndOpensAudioMode() async throws {
        var item = record()
        item.mediaKind = .audio
        let directory = try PiliOfflineStorage.directory(item.id)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try PiliOfflineStorage.part(item.id, .audio)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 132_300))
        buffer.frameLength = 132_300
        if let samples = buffer.floatChannelData?[0] { samples.initialize(repeating: 0, count: 132_300) }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000]
        // Closing the writer finalizes the container before AVAsset reads it.
        do {
            let writer = try AVAudioFile(forWriting: source, settings: settings,
                                         commonFormat: .pcmFormatFloat32, interleaved: false)
            try writer.write(from: buffer)
        }
        let output = try await PiliOfflineMediaExporter.finalize(item)
        let asset = AVURLAsset(url: output)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        XCTAssertFalse(audio.isEmpty)
        XCTAssertTrue(video.isEmpty)
        item.state = .completed
        item.outputFileName = output.lastPathComponent
        XCTAssertEqual(try PiliOfflineStorage.playbackURL(item), output)
        let model = PiliOfflinePlaybackModel(item: item, url: output)
        XCTAssertEqual(model.player.playbackContentMode, .audioOnly)
        defer { model.player.stop() }
        model.player.play()
        let deadline = Date().addingTimeInterval(8)
        while (model.player.playbackClock.currentTime < 0.05 || !model.player.hasPresentedPlayback), model.player.errorMessage == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(model.player.errorMessage)
        XCTAssertGreaterThan(model.player.playbackClock.currentTime, 0.05, "Exported audio must advance the production player's clock offline")
        XCTAssertTrue(model.player.hasPresentedPlayback, "Audio must leave startup suppression without a video surface")
        model.player.pause()
        XCTAssertFalse(model.player.isPlaying)
        model.player.seek(to: 0.5)
        XCTAssertEqual(model.player.playbackClock.currentTime, 1.5, accuracy: 0.15, "The audio slider commits normalized progress")
        model.player.play()
        let resumedDeadline = Date().addingTimeInterval(8)
        while model.player.playbackClock.currentTime < 2, model.player.errorMessage == nil, Date() < resumedDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(model.player.errorMessage)
        XCTAssertGreaterThanOrEqual(model.player.playbackClock.currentTime, 2, "Audio must resume after a paused seek")
    }

    func testCorruptMediaIsNeverAcceptedAsCompletedExport() async throws {
        var item = record()
        item.mediaKind = .audio
        let directory = try PiliOfflineStorage.directory(item.id)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("<html>error</html>".utf8).write(to: PiliOfflineStorage.part(item.id, .audio))
        do {
            _ = try await PiliOfflineMediaExporter.finalize(item)
            XCTFail("Corrupt media must not produce a completed asset")
        } catch { }
    }

    private func record() -> OfflineDownloadItem {
        OfflineDownloadItem(bvid: "BVoffline", cid: 7, title: "下载", author: "UP", coverURL: nil,
                            duration: 1, quality: 80, qualityTitle: "1080P", codec: "avc1")
    }
    private func playData() throws -> PlayURLData {
        try JSONDecoder().decode(PlayURLData.self, from: Data(#"{"quality":80,"accept_quality":[80],"dash":{"duration":1,"video":[{"id":80,"baseUrl":"https://example.com/video.m4s","codecs":"avc1.640028","codecid":7,"mimeType":"video/mp4","width":1920,"height":1080}],"audio":[{"id":30280,"baseUrl":"https://example.com/audio.m4s","codecs":"mp4a.40.2","mimeType":"audio/mp4","bandwidth":192000}]}}"#.utf8))
    }
}
