import XCTest
import ImageIO
import UniformTypeIdentifiers
import PiliPlaybackCore
@testable import bili

@MainActor
final class PiliSocialContentTests: XCTestCase {
    func testDynamicPayloadKeepsNumericTypesAndAllPublishingOptions() throws {
        var draft = PiliDynamicDraft()
        draft.tokens = [.init(text: "你好 "), .init(text: "@用户", type: 2, businessID: "123")]
        draft.topicID = 42; draft.topicName = "话题"; draft.voteID = 19; draft.voteTitle = "投票"
        draft.privatePost = true; draft.commentPolicy = 2; draft.repostID = "876543210123456789"
        draft.editingID = "876543210123456790"; draft.scheduledAt = Date().addingTimeInterval(3600)
        let encoded = try JSONEncoder().encode(draft.payload(mid: 7, uploadID: "upload"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let request = try XCTUnwrap(json["dyn_req"] as? [String: Any])
        XCTAssertEqual(request["scene"] as? Int, 4)
        XCTAssertEqual(json["dyn_id_str"] as? String, draft.editingID)
        let options = try XCTUnwrap(request["option"] as? [String: Any])
        XCTAssertEqual(options["private_pub"] as? Int, 1)
        XCTAssertEqual(options["up_choose_comment"] as? Int, 1)
        let contents = try XCTUnwrap((request["content"] as? [String: Any])?["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.map { $0["type"] as? Int }, [1, 2, 4])
        XCTAssertEqual(contents[1]["biz_id"] as? String, "123")
        XCTAssertEqual(contents[2]["biz_id"] as? String, "19")
    }
    func testDynamicValidationRunsBeforePhotoUploads() throws {
        var draft = PiliDynamicDraft()
        XCTAssertThrowsError(try draft.validate())
        XCTAssertNoThrow(try draft.validate(pendingImages: 1))
        XCTAssertThrowsError(try draft.validate(pendingImages: 10))
        draft.tokens = [.init(text: "@坏用户", type: 2, businessID: "0")]
        XCTAssertThrowsError(try draft.validate(pendingImages: 1))
        draft.tokens = [.init(text: "内容")]; draft.scheduledAt = Date().addingTimeInterval(-1)
        XCTAssertThrowsError(try draft.validate())
    }
    func testMentionsUseSelectedUIDAndDoNotRewriteLongerNames() {
        let mentions = [PiliNamedResource(id: 12, name: "猫"), PiliNamedResource(id: 13, name: "猫猫")]
        let tokens = PiliDynamicComposer.tokens(from: [.text("你好 @猫猫 ，@猫 更多@猫咪"), .emote("[doge]")], mentions: mentions)
        XCTAssertEqual(tokens.map(\.text).joined(), "你好 @猫猫 ，@猫 更多@猫咪[doge]")
        XCTAssertEqual(tokens.filter { $0.type == 2 }.map(\.businessID), ["13", "12"])
        XCTAssertEqual(tokens.last?.type, 9)
    }
    func testDraftImagesAreNotRewrittenOnEveryKeystrokeAndRemainAccountScoped() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PiliDraftStorage(root: root)
        let image = PiliDraftStorage.Image(id: UUID(), data: Data([1, 2, 3]))
        var draft = PiliDynamicDraft(); draft.tokens = [.init(text: "草稿")]
        try await store.save(draft, images: [image], key: "1.dynamic.new")
        let dir = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first { $0.pathExtension == "jpg" })
        let originalDate = Date(timeIntervalSince1970: 100)
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: file.path)
        draft.tokens.append(.init(text: "变更"))
        try await store.save(draft, images: [image], key: "1.dynamic.new")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date, originalDate)
        let own = try await store.load(key: "1.dynamic.new"), other = try await store.load(key: "2.dynamic.new")
        XCTAssertEqual(own?.0.plainText, "草稿变更"); XCTAssertEqual(own?.1.first?.data, image.data); XCTAssertNil(other)
        try await store.remove(key: "1.dynamic.new")
        let removed = try await store.load(key: "1.dynamic.new"); XCTAssertNil(removed)
    }
    func testPhotoPreparationBoundsDecodedPixelsAndAppliesOrientation() async throws {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: 2000, height: 1000, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try XCTUnwrap(context.makeImage()), bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let result = await PiliImagePreparation.jpeg(bytes as Data, maxPixelSize: 500)
        let output = try XCTUnwrap(result)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 250)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 500)
        let invalid = await PiliImagePreparation.jpeg(Data("not an image".utf8))
        XCTAssertNil(invalid)
    }
    func testMessageSettingsSelectionRetainsUnknownFields() throws {
        var first = PiliProtoMessage(); first.set(1, integer: 1); first.set(2, string: "所有人"); first.set(3, integer: 1)
        var second = PiliProtoMessage(); second.set(1, integer: 2); second.set(2, string: "仅关注的人")
        var choices = PiliProtoMessage(); choices.set(1, messages: [first, second]); choices.set(100, string: "future")
        var raw = PiliProtoMessage(); raw.set(2, message: choices); raw.set(101, integer: 42)
        let setting = PiliIMSetting(id: 10, raw: raw).selecting(1)
        XCTAssertEqual(setting.choices.map { $0.integer(3) }, [0, 1])
        XCTAssertEqual(try setting.raw.message(2).string(100), "future")
        XCTAssertEqual(setting.raw.integer(101), 42)
        XCTAssertEqual(try setting.updateRequest.messages(1).first?.integer(1), 10)
    }
}
