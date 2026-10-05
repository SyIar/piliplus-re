import Foundation
import Testing
@testable import PiliPlaybackCore

@Test func settingsBackupPreservesTypedValuesAndExcludesCredentialsAndPlaybackSessions() throws {
    let values: [String: Any] = ["cc.bili.playback.defaultPlaybackRate.v1": 1.5,
                               "cc.bili.content.blockedDynamicKeywords.v1": ["a", "b"],
                               "piliplus.subtitle.bold": true,
                               "piliplus.player.lockOrientation": false,
                               "piliplus.audio.quality": "best",
                               "piliplus.audio.cellularQuality": "compatible",
                               "JKBili.Session.Fallback.SESSDATA": "secret",
                               "piliplus.webdav.password": "secret",
                               "cc.bili.playback.progressByBVID.v1": Data([1,2]),
                               "piliplus.interactive.123.BV123.3": "history"]
    let data = try JSONEncoder().encode(SettingsArchive.capture(values))
    let restored = try SettingsArchive.decode(data).decodedValues()
    #expect(restored.count == 6)
    #expect(restored["piliplus.player.lockOrientation"] as? Bool == false)
    #expect(restored["piliplus.audio.quality"] as? String == "best")
    #expect(restored["piliplus.audio.cellularQuality"] as? String == "compatible")
    #expect(restored["cc.bili.playback.defaultPlaybackRate.v1"] as? Double == 1.5)
    #expect(restored["cc.bili.content.blockedDynamicKeywords.v1"] as? [String] == ["a", "b"])
    #expect(!String(decoding: data, as: UTF8.self).contains("secret"))
}
@Test func invalidBackupIsRejectedBeforeAnySettingsCanBeApplied() throws {
    let archive = SettingsArchive(values: ["piliplus.subtitle.bold": Data("not a plist".utf8)])
    #expect(throws: (any Error).self) { try SettingsArchive.decode(JSONEncoder().encode(archive)) }
    let data = Data(#"{"format":"other-app","version":1,"createdAt":0,"values":{}}"#.utf8)
    #expect(throws: (any Error).self) { try SettingsArchive.decode(data) }
}
