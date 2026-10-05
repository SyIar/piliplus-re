import Foundation
import Testing
@testable import PiliPlaybackCore

@Test func audioOnlyDownloadNeverRequiresOrAcceptsVideoCompletion() throws {
    var item = OfflineDownloadItem(bvid: "BVaudio", cid: 7, title: "音频", author: "UP", coverURL: nil,
                                  duration: 30, quality: 0, qualityTitle: "AAC", codec: "mp4a.40.2")
    item.mediaKind = .audio
    item.state = .downloading
    #expect(item.requiredParts == [.audio])
    #expect(!item.accepts(OfflineTaskIdentity(itemID: item.id, generation: item.generation, part: .video)))
    item.completedParts = [.video]
    #expect(!item.isReadyToFinalize)
    item.completedParts = [.audio]
    #expect(item.isReadyToFinalize)
    item.expectedBytes = [.audio: 200]
    item.receivedBytes = [.audio: 50]
    #expect(item.progress == 0.25)
    let restored = try JSONDecoder().decode(OfflineDownloadItem.self, from: JSONEncoder().encode(item))
    #expect(restored.effectiveMediaKind == .audio)
    var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
    legacy.removeValue(forKey: "mediaKind")
    legacy.removeValue(forKey: "audioQualityID")
    let old = try JSONDecoder().decode(OfflineDownloadItem.self, from: JSONSerialization.data(withJSONObject: legacy))
    #expect(old.effectiveMediaKind == .video)
    #expect(old.requiredParts == [.video, .audio])
}

@Test func downloadValidationAcceptsWholeFilesAndReassembledResumeFiles() throws {
    try OfflineDownloadValidation.validate(status: 200, mimeType: "video/mp4", contentLength: 500,
        contentRange: nil, contentEncoding: nil, fileSize: 500)
    try OfflineDownloadValidation.validate(status: 206, mimeType: "audio/mp4", contentLength: 400,
        contentRange: "bytes 100-499/500", contentEncoding: nil, fileSize: 500)
    try OfflineDownloadValidation.validate(status: 200, mimeType: "application/octet-stream", contentLength: -1,
        contentRange: nil, contentEncoding: nil, fileSize: 700)
}

@Test func downloadValidationRejectsErrorsTruncationAndInvalidRanges() {
    func rejects(_ status: Int, _ type: String?, _ length: Int64, _ range: String?, _ size: Int64) {
        #expect(throws: OfflineDownloadValidation.Failure.self) {
            try OfflineDownloadValidation.validate(status: status, mimeType: type, contentLength: length,
                contentRange: range, contentEncoding: nil, fileSize: size)
        }
    }
    rejects(200, "text/html", 500, nil, 500)
    rejects(200, "application/problem+json", 500, nil, 500)
    rejects(200, "video/mp4", 500, nil, 499)
    rejects(200, "audio/mp4", -1, nil, 0)
    rejects(416, "audio/mp4", 500, "bytes */500", 500)
    rejects(206, "audio/mp4", 400, "bytes 100-499/500", 400)
    rejects(206, "audio/mp4", 100, "bytes 0-99/500", 100)
    rejects(206, "audio/mp4", 400, "bytes 100-499/*", 500)
    rejects(206, "audio/mp4", 399, "bytes 100-499/500", 500)
    rejects(206, "audio/mp4", 500, nil, 500)
}
