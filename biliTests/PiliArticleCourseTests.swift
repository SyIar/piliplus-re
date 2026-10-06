import XCTest
@testable import bili

final class PiliArticleCourseTests: XCTestCase {
    func testCourseUsesDedicatedIdentityDurationAndReplyTarget() throws {
        let input = try JSONDecoder().decode(DynamicJSONValue.self, from: Data(#"{"season_id":90,"title":"课程","up_info":{"mid":10,"name":"老师","face":"https://example.com/a.jpg"},"episodes":[{"id":91,"aid":999,"bvid":"BVnormal","cid":92,"title":"第一课","duration":10800}]}"#.utf8))
        let season = try BiliAPIClient.piliCourseSeason(input)
        let video = try XCTUnwrap(season.preferredPlaybackEpisode?.videoItem(in: season))
        XCTAssertEqual(video.bvid, "pugv-ep91")
        XCTAssertTrue(video.piliIsCourse); XCTAssertTrue(video.isPGCEpisode)
        XCTAssertEqual(video.duration, 10800, "PUGV durations are seconds, including long courses")
        XCTAssertEqual(video.owner?.name, "老师")
        let target = try XCTUnwrap(VideoDetailCommentTarget(detail: video))
        XCTAssertEqual(target.oid, "91", "The comment target is episode ID even when aid is present")
        XCTAssertEqual(target.type, 33)
    }
    func testContentRoutesValidateHostAndKeepIDNamespace() throws {
        XCTAssertEqual(PiliCourseRoute(url: try XCTUnwrap(URL(string: "https://www.bilibili.com/cheese/play/ep123")))?.episodeID, 123)
        XCTAssertNil(PiliCourseRoute(url: try XCTUnwrap(URL(string: "https://bilibili.com.evil.invalid/cheese/play/ep123"))))
        XCTAssertEqual(PiliArticleRoute(url: try XCTUnwrap(URL(string: "bilibili://article/123")))?.kind, .read)
        XCTAssertEqual(PiliArticleRoute(url: try XCTUnwrap(URL(string: "https://www.bilibili.com/opus/987654321098765432")))?.id, "987654321098765432")
        XCTAssertNil(PiliArticleRoute(url: try XCTUnwrap(URL(string: "https://example.com/read/cv123"))))
    }
    func testOpusModulesRetainBodyAndCommentIdentity() throws {
        let body = try JSONDecoder().decode(DynamicJSONValue.self, from: Data(#"{"item":{"id_str":"987654321098765432","basic":{"comment_id_str":"123","comment_type":12},"modules":[{"module_type":"MODULE_TYPE_TITLE","module_title":{"text":"标题"}},{"module_type":"MODULE_TYPE_AUTHOR","module_author":{"mid":7,"name":"作者"}},{"module_type":"MODULE_TYPE_CONTENT","module_content":{"paragraphs":[{"para_type":1,"text":{"nodes":[{"word":{"words":"正文"}}]}}]}}]}}"#.utf8))
        let doc = PiliArticleDocument(route: .init(id: "987654321098765432", kind: .opus), body: body)
        XCTAssertEqual(doc.title, "标题"); XCTAssertEqual(doc.author?.mid, 7); XCTAssertEqual(doc.paragraphs.count, 1)
        let target = try doc.commentTarget()
        XCTAssertEqual(target.commentOID, "123"); XCTAssertEqual(target.commentType, 12)
    }
    func testLegacyArticlePreservesHTMLAndTypedOperations() throws {
        let body = try JSONDecoder().decode(DynamicJSONValue.self, from: Data(#"{"id":123,"content":"<p>正文</p>","dyn_id_str":"999","ops":[{"insert":"段落","attributes":{"bold":true}}]}"#.utf8))
        let doc = PiliArticleDocument(route: .init(id: "123", kind: .read), body: body, info: .object(["title": .string("文章"), "favorite": .bool(true)]))
        XCTAssertEqual(doc.html, "<p>正文</p>"); XCTAssertEqual(doc.operations.count, 1); XCTAssertTrue(doc.favorited)
        XCTAssertEqual(doc.commentType, 12); XCTAssertEqual(doc.commentID, 123)
    }
}
