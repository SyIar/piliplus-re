import XCTest
@testable import bili

@MainActor
final class PiliAudioLanguageTests: XCTestCase {
    func testAudioLanguageMetadataSurvivesDisplayAndHistoryTransforms() throws {
        let value = try data(language: "zh-CN", audio: "translated")
        XCTAssertEqual(value.language?.items?.first?.productionType, 2)
        XCTAssertEqual(value.removingHistoryMetadata().curLanguage, "zh-CN")
        XCTAssertEqual(value.mergingDisplayFormats(from: try data(language: "en-US", audio: "original")).curLanguage, "zh-CN")
    }
    func testDifferentLanguageAudioCannotBeMergedOrReusedAsSameVariant() throws {
        let translated = try data(language: "zh-CN", audio: "translated")
        let original = try data(language: "en-US", audio: "original")
        let merged = translated.mergingPlayableStreams(from: original)
        XCTAssertEqual(merged.dash?.audio?.count, 1)
        XCTAssertEqual(merged.dash?.audio?.first?.playURL?.lastPathComponent, "translated.m4s")
        XCTAssertNotEqual(translated.playVariants.first?.id, original.playVariants.first?.id)
        XCTAssertNotNil(translated.playVariants.first)
    }
    private func data(language: String, audio: String) throws -> PlayURLData {
        let json = """
        {"quality":80,"cur_language":"\(language)","language":{"support":true,"items":[{"lang":"zh-CN","title":"中文","production_type":2,"subtitle_lang":"ai-zh"}]},"dash":{"video":[{"id":80,"baseUrl":"https://example.com/video.m4s","codecs":"avc1.640028","codecid":7,"width":1920,"height":1080}],"audio":[{"id":30280,"baseUrl":"https://example.com/\(audio).m4s","codecs":"mp4a.40.2"}]}}
        """
        return try JSONDecoder().decode(PlayURLData.self, from: Data(json.utf8))
    }
}
