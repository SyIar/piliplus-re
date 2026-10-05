import Foundation
import Testing
@testable import PiliPlaybackCore

@Test func overlappingSubtitlesHaveHalfOpenBoundsAndSupportSeekingBack() {
    let timeline = SubtitleTimeline([
        .init(from: 1, to: 10, content: "long"), .init(from: 3, to: 5, content: "short"),
        .init(from: 4, to: 4, content: "invalid"), .init(from: .nan, to: 8, content: "invalid")
    ])
    #expect(timeline.active(at: 4).map(\.content) == ["long", "short"])
    #expect(timeline.active(at: 5).map(\.content) == ["long"])
    #expect(timeline.active(at: 10).isEmpty)
    #expect(timeline.active(at: 2).map(\.content) == ["long"])
    #expect(timeline.active(at: -.infinity).isEmpty)
}
@Test func subtitleTextImportHandlesVttSettingsCRLFAndMultiline() {
    let text = "WEBVTT\r\n\r\nidentifier\r\n00:01.250 --> 00:03.000 align:start\r\n<b>你好</b>\r\nWorld &amp; friends\r\n\r\n2\r\n00:00:05,000 --> 00:00:07,000\r\n第二条\r\n"
    let cues = SubtitleTextCodec.parse(text)
    #expect(cues.count == 2)
    #expect(cues.first?.from == 1.25)
    #expect(cues.first?.content == "你好\nWorld & friends")
    #expect(SubtitleTextCodec.parse(SubtitleTextCodec.srt(cues)) == cues)
    #expect(SubtitleTextCodec.parse(SubtitleTextCodec.vtt(cues)) == cues)
}
