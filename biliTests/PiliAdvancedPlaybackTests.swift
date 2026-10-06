import XCTest
import UIKit
import PiliPlaybackCore
@testable import bili

@MainActor
final class PiliAdvancedPlaybackTests: XCTestCase {
    func testGuestSubtitleWireFieldsAndAIMarker() throws {
        var track = PiliProtoMessage()
        track.set(3, string: "ai-zh"); track.set(4, string: "中文（自动）")
        track.set(5, string: "//aisubtitle.hdslb.com/test.json"); track.set(7, integer: 1)
        var list = PiliProtoMessage(); list.set(3, messages: [track, track, .init()])
        var response = PiliProtoMessage(); response.set(3, message: list)
        let values = try BiliAPIClient.piliGuestSubtitleTracks(response)
        XCTAssertEqual(values.count, 1)
        XCTAssertTrue(values[0].isAI)
        XCTAssertEqual(values[0].lan, "ai-zh")
        XCTAssertEqual(values[0].subtitleURL, "//aisubtitle.hdslb.com/test.json")
    }

    func testAdvancedDanmakuSeeksAndOnlyHitsVisibleText() throws {
        let view = DanmakuAnimationOverlayView(frame: CGRect(x: 0, y: 0, width: 640, height: 360))
        view.onSelect = { _ in }
        view.layoutIfNeeded()
        let value = DanmakuItem(id: "special", time: 1, mode: 7, fontSize: 25, color: 0xFFFFFF,
            text: "[0.1,0.2,\"1-1\",10,\"高级\",0,0,0.8,0.7,8000,0,true]", serverID: "99", cid: 42)
        func apply(_ time: Double, settings: DanmakuSettings = .default) {
            view.apply(items: [value], itemsRevision: 1, currentTime: time, isPlaying: false, playbackRate: 1,
                isEnabled: true, hasPresentedPlayback: true, isLoadShedding: false, settings: settings,
                topInset: 8, bottomInset: 54)
        }
        apply(1)
        let first = try XCTUnwrap(view.subviews.compactMap { $0 as? UILabel }.first)
        XCTAssertEqual(first.layer.position.x, 64, accuracy: 1)
        XCTAssertEqual(first.layer.position.y, 72, accuracy: 1)
        XCTAssertTrue(view.point(inside: CGPoint(x: 75, y: 80), with: nil))
        XCTAssertFalse(view.point(inside: CGPoint(x: 600, y: 330), with: nil))
        apply(9)
        let later = try XCTUnwrap(view.subviews.compactMap { $0 as? UILabel }.first)
        XCTAssertEqual(later.layer.position.x, 512, accuracy: 1)
        apply(1)
        XCTAssertEqual(try XCTUnwrap(view.subviews.compactMap { $0 as? UILabel }.first).layer.position.x, 64, accuracy: 1)
        var hidden = DanmakuSettings.default; hidden.showsAdvanced = false
        apply(1, settings: hidden)
        XCTAssertFalse(view.point(inside: CGPoint(x: 75, y: 80), with: nil))
        view.stop()
    }

    func testOfflineDanmakuKeepsVIPColorAndOldFilesDecode() throws {
        let value = DanmakuItem(id: "vip", time: 1, mode: 1, fontSize: 25, color: 0xFFFFFF, text: "会员", isVIPColor: true)
        let restored = try JSONDecoder().decode(PiliOfflineDanmaku.self, from: JSONEncoder().encode(PiliOfflineDanmaku(value)))
        XCTAssertTrue(restored.item.isVIPColor)
        let legacy = Data(#"{"id":"old","time":0,"mode":1,"fontSize":25,"color":16777215,"text":"弹幕"}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(PiliOfflineDanmaku.self, from: legacy).item.isVIPColor)
    }
}
