import Foundation
import XCTest
import PiliPlaybackCore
@testable import bili

final class PiliSupplementTests: XCTestCase {
    func testSupplementRoutesUseExactHostsAndPreserveNamespaces() throws {
        XCTAssertEqual(PiliSupplementRoute(url: URL(string: "https://www.bilibili.com/audio/au123?from=share")!), .audio(123))
        XCTAssertEqual(PiliSupplementRoute(url: URL(string: "bilibili://audio/456")!), .audio(456))
        XCTAssertEqual(PiliSupplementRoute(url: URL(string: "https://music.bilibili.com/h5/music-detail?music_id=MA102")!), .music("MA102"))
        XCTAssertEqual(PiliSupplementRoute(url: URL(string: "https://www.bilibili.com/bubble/home/12")!), .bubble("12"))
        XCTAssertEqual(PiliSupplementRoute(url: URL(string: "https://www.bilibili.com/match/data/detail/89")!), .match(89))
        XCTAssertNil(PiliSupplementRoute(url: URL(string: "https://www.bilibili.com.evil.test/audio/au123")!))
        XCTAssertNil(PiliSupplementRoute(url: URL(string: "https://www.bilibili.com/audio/au-1")!))
        XCTAssertNil(PiliSupplementRoute(url: URL(string: "file://www.bilibili.com/audio/au123")!))
        XCTAssertNil(PiliSupplementRoute(url: URL(string: "https://music.bilibili.com/h5/music-detail?music_id=MA1%26x=2")!))
    }
    func testAudioPlaylistPreservesAUTypeCursorAndSort() throws {
        let initial = PiliAudioCodec.playlist(id: 123, cursor: nil, order: .reverse)
        XCTAssertEqual(initial.integer(1), 3)
        XCTAssertEqual(try initial.message(3).integer(1), 3)
        XCTAssertEqual(try initial.message(3).integer(3), 123)
        XCTAssertEqual(try initial.message(7).integer(1), 2)
        let next = PiliAudioCodec.playlist(id: 123, cursor: "opaque-next", order: .random)
        XCTAssertFalse(next.has(1)); XCTAssertFalse(next.has(3))
        XCTAssertEqual(try next.message(8).string(2), "opaque-next")
        XCTAssertEqual(try next.message(5).integer(4), 2)
    }
    func testAudioDecodeUsesMapValueAndRejectsMissingOrUnsafeURLs() throws {
        var audio = PiliProtoMessage(); audio.set(1, integer: 30280); audio.set(2, string: "https://audio.example.com/song.m4a")
        var dash = PiliProtoMessage(); dash.set(1, integer: 180); dash.set(3, messages: [audio])
        var info = PiliProtoMessage(); info.set(5, message: dash)
        var map = PiliProtoMessage(); map.set(1, integer: 99); map.set(2, message: info)
        var response = PiliProtoMessage(); response.set(4, messages: [map])
        let sources = try PiliAudioSource.decode(response)
        XCTAssertEqual(sources.first?.id, 30280); XCTAssertEqual(sources.first?.duration, 180)
        XCTAssertEqual(sources.first?.url.host, "audio.example.com")
        audio.set(2, string: "file:///etc/passwd"); dash.set(3, messages: [audio]); info.set(5, message: dash); map.set(2, message: info); response.set(4, messages: [map])
        XCTAssertThrowsError(try PiliAudioSource.decode(response))
        XCTAssertThrowsError(try PiliAudioSource.decode(.init()))
    }
    func testArchiveRoundTripIsolationDedupAndUpstreamImport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = PiliCommentArchive(root: root)
        let first = PiliSavedComment(account: 42, id: 101, oid: "7", type: 1, root: 0, parent: 0, message: "你好", pictures: [], created: 100)
        try await archive.record(first); try await archive.record(first)
        let values = try await archive.comments(account: 42), other = try await archive.comments(account: 43)
        XCTAssertEqual(values, [first]); XCTAssertTrue(other.isEmpty)
        let bytes = try await archive.export(account: 42)
        let duplicate = try await archive.merge(bytes, account: 42); XCTAssertEqual(duplicate, 0)
        do { _ = try await archive.merge(bytes, account: 43); XCTFail("Must reject another author's archive") } catch {}
        let flutter = Data(#"[{"id":"102","oid":"8","type":"14","ctime":"200","member":{"mid":"42"},"content":{"message":"音频评论"}}]"#.utf8)
        let added = try await archive.merge(flutter, account: 42); XCTAssertEqual(added, 1)
        let after = try await archive.comments(account: 42)
        XCTAssertEqual(after.map(\.id), [102,101]); XCTAssertEqual(after[0].contextURL?.path, "/audio/au8")
        try await archive.remove(id: 101, account: 42)
        let remaining = try await archive.comments(account: 42); XCTAssertEqual(remaining.count, 1)
    }
    func testArchiveRejectsCorruptOrUnboundedImportWithoutReplacingExisting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = PiliCommentArchive(root: root)
        let comment = PiliSavedComment(account: 1, id: 1, oid: "2", type: 1, root: 0, parent: 0, message: "保留", pictures: [], created: 1)
        try await archive.record(comment)
        do { _ = try await archive.merge(Data("[{\"account\":1}]".utf8), account: 1); XCTFail("Corrupt import") } catch {}
        do { _ = try await archive.merge(Data(repeating: 0, count: 16 * 1024 * 1024 + 1), account: 1); XCTFail("Oversized import") } catch {}
        let values = try await archive.comments(account: 1); XCTAssertEqual(values, [comment])
    }
}
