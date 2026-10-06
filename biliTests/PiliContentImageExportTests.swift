import ImageIO
import XCTest
@testable import bili

@MainActor
final class PiliContentImageExportTests: XCTestCase {
    func testLongContentCreatesBoundedReadablePages() async throws {
        let document = PiliContentImageDocument(title: "评论", author: "测试用户",
            text: String(repeating: "完整保存内容，不按屏幕高度截断。\n", count: 100), pictures: [], source: "https://www.bilibili.com/video/BVtest")
        let files = try await PiliContentImageExport.render(document)
        defer { PiliMediaCapture.remove(files.first) }
        XCTAssertGreaterThan(files.count, 1)
        for file in files {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(file as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, 1080); XCTAssertEqual(image.height, 1440)
        }
    }
    func testInvalidAttachmentDoesNotReturnIncompleteContent() async {
        do {
            _ = try await PiliContentImageExport.render(.init(title: "动态", author: "UP", text: "附图不能静默丢失", pictures: ["file:///private/image.jpg"], source: "https://t.bilibili.com/1"))
            XCTFail("An incomplete export must never be reported as successful")
        } catch { XCTAssertTrue(error.localizedDescription.contains("地址")) }
    }
}
