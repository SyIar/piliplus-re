import Foundation
import Testing
@testable import PiliPlaybackCore

@Test func offlineCollectionsAreBackwardCompatibleAndKeepDifferentCoursesApart() throws {
    var item = OfflineDownloadItem(bvid: "BVtest", cid: 42, title: "分集", author: "UP", coverURL: nil,
        duration: 60, quality: 80, qualityTitle: "1080P", codec: "avc1", seasonID: 12)
    #expect(item.collectionKey == "season:12")
    item.collectionID = "ugc:55"; item.collectionTitle = "合集"
    let data = try JSONEncoder().encode(item)
    #expect(try JSONDecoder().decode(OfflineDownloadItem.self, from: data).collectionKey == "ugc:55")
    var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    legacy.removeValue(forKey: "collectionID"); legacy.removeValue(forKey: "collectionTitle")
    let restored = try JSONDecoder().decode(OfflineDownloadItem.self, from: JSONSerialization.data(withJSONObject: legacy))
    #expect(restored.collectionKey == "season:12")
}
