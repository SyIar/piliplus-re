import Foundation
import Testing
@testable import PiliPlaybackCore

private func item() -> OfflineDownloadItem {
    OfflineDownloadItem(bvid: "BV1offline", cid: 12, title: "Download", author: "UP", coverURL: nil,
                        duration: 60, quality: 80, qualityTitle: "1080P", codec: "avc1")
}

@Test func offlineIdentityRejectsMalformedAndTraversalValues() {
    let record = item()
    let identity = OfflineTaskIdentity(itemID: record.id, generation: record.generation, part: .video)
    #expect(OfflineTaskIdentity(taskDescription: identity.taskDescription) == identity)
    #expect(OfflineTaskIdentity(taskDescription: "../../other|video") == nil)
    #expect(OfflineTaskIdentity(taskDescription: identity.taskDescription + "|extra") == nil)
}

@Test func pausedOrRetriedDownloadRejectsLateCompletion() {
    var record = item()
    record.state = .downloading
    let old = OfflineTaskIdentity(itemID: record.id, generation: record.generation, part: .video)
    #expect(record.accepts(old))
    record.state = .paused
    #expect(!record.accepts(old))
    record.state = .downloading
    record.generation = UUID()
    #expect(!record.accepts(old))
}

@Test func separateAudioMustFinishBeforeOfflineFileIsPlayable() {
    var record = item()
    record.completedParts.insert(.video)
    #expect(!record.isReadyToFinalize)
    record.completedParts.insert(.audio)
    #expect(record.isReadyToFinalize)
    record.completedParts.remove(.audio)
    record.requiresAudio = false
    #expect(record.isReadyToFinalize)
}

@Test func offlineProgressHandlesUnknownLengthsAndPersistence() throws {
    var record = item()
    #expect(record.progress == nil)
    record.expectedBytes = [.video: 100, .audio: 20]
    record.receivedBytes = [.video: 50, .audio: 10]
    #expect(record.progress == 0.5)
    record.completedParts.insert(.audio)
    let restored = try JSONDecoder().decode(OfflineDownloadItem.self, from: JSONEncoder().encode(record))
    #expect(restored == record)
}
