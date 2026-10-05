import XCTest
@testable import bili

@MainActor
final class PlaybackAudioQualityTests: H264PlaybackTestCase {
    func testBestAvailableQualityAndCompatibleFallbackPreserveVideo() throws {
        let data = try JSONDecoder().decode(PlayURLData.self, from: Data(#"{"quality":80,"dash":{"video":[{"id":80,"baseUrl":"https://example.com/video.m4s","codecs":"avc1.640028","codecid":7}],"audio":[{"id":30280,"baseUrl":"https://example.com/aac.m4s","codecs":"mp4a.40.2","bandwidth":192000},{"id":30250,"baseUrl":"https://example.com/dolby.m4s","codecs":"ec-3","bandwidth":384000},{"id":30251,"baseUrl":"https://example.com/lossless.m4s","codecs":"flac","bandwidth":1000000}]}}"#.utf8))
        let dash = try XCTUnwrap(data.dash)
        XCTAssertEqual(dash.preferredAudioStream(.best)?.id, 30251)
        XCTAssertEqual(dash.preferredAudioStream(.compatible)?.id, 30280)
        let best = try XCTUnwrap(data.playVariants(cdnPreference: .automatic, codecPreference: .forceH264, audioQuality: .best).first)
        XCTAssertEqual(best.audioURL?.lastPathComponent, "lossless.m4s")
        let aac = try XCTUnwrap(dash.bestAudioStream)
        let fallback = try XCTUnwrap(best.replacingAudio(with: aac, cdn: .automatic, prefersBackup: false))
        XCTAssertEqual(fallback.videoURL, best.videoURL)
        XCTAssertEqual(fallback.quality, best.quality)
        XCTAssertNotEqual(fallback.id, best.id)
        XCTAssertEqual(fallback.audioURL?.lastPathComponent, "aac.m4s")
        let onlyAAC = DASHInfo(duration: nil, video: nil, audio: [aac])
        XCTAssertEqual(onlyAAC.preferredAudioStream(.best), aac)
        XCTAssertNil(DASHInfo(duration: nil, video: nil, audio: []).preferredAudioStream(.best))
    }

    func testAudioPreferencesPersistSeparatelyForCellularAndWiFi() throws {
        let name = "audio-quality-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = LibraryStore(userDefaults: defaults)
        store.setAudioQualityPreference(.best)
        let restored = LibraryStore(userDefaults: defaults)
        XCTAssertEqual(restored.audioQualityPreference, .best)
        XCTAssertEqual(restored.cellularAudioQualityPreference, .compatible)
        XCTAssertEqual(PlaybackAudioQualityPreference.stored(in: defaults, network: .wifi), .best)
        XCTAssertEqual(PlaybackAudioQualityPreference.stored(in: defaults, network: .constrained), .compatible)
        restored.setAudioQualityPreference(.best, cellular: true)
        XCTAssertEqual(PlaybackAudioQualityPreference.stored(in: defaults, network: .cellular), .best)
    }
}
