import CoreText
import Foundation
import ImageIO
import Photos
import UIKit

nonisolated struct PiliContentImageDocument: Sendable {
    let title: String
    let author: String
    let text: String
    let pictures: [String]
    let source: String

    static func comment(_ comment: Comment, source: String) -> Self {
        .init(title: "评论", author: comment.member?.uname ?? "", text: comment.content?.message ?? "",
            pictures: (comment.content?.pictures ?? []).map(\.url), source: source)
    }
    static func dynamic(_ item: DynamicFeedItem) -> Self {
        var text = item.displayText ?? "", pictures = item.imageItems.map(\.url)
        func appendCard(_ module: DynamicModuleDynamic?) {
            if let archive = module?.major?.resolvedArchive {
                text += "\n\n视频：" + (archive.title ?? "")
                if let desc = archive.desc, !desc.isEmpty { text += "\n" + desc }
                if let bvid = archive.bvid { text += "\nhttps://www.bilibili.com/video/" + bvid }
                if let cover = archive.cover, !cover.isEmpty { pictures.append(cover) }
            }
            if let paid = module?.paidContent {
                text += "\n\n" + paid.title
                if let subtitle = paid.subtitle { text += "\n" + subtitle }
                if let cover = paid.cover, !cover.isEmpty { pictures.append(cover) }
            }
            let additional = module?.additional?.raw ?? .null
            let vote = additional["vote"], reserve = additional["reserve"]
            if vote["vote_id"].piliInt > 0 { text += "\n\n投票：" + vote["desc"].piliString }
            if reserve["rid"].piliInt > 0 {
                text += "\n\n预约：" + reserve["title"].piliString + "\n" + reserve["desc1"]["text"].piliString + " " + reserve["desc2"]["text"].piliString
            }
        }
        appendCard(item.modules?.moduleDynamic)
        if let original = item.original {
            text += "\n\n转发自 " + (original.author?.name ?? "") + "\n" + (original.displayText ?? "")
            pictures += original.imageItems.map(\.url); appendCard(original.modules?.moduleDynamic)
        }
        var seen = Set<String>(); pictures = pictures.filter { seen.insert($0.normalizedBiliURL()).inserted }
        return .init(title: "动态", author: item.author?.name ?? "", text: text,
            pictures: pictures, source: "https://t.bilibili.com/" + item.idStr)
    }

}

nonisolated enum PiliContentImageExport {
    /// Fixed-size pages avoid allocating an unbounded long screenshot. All text and
    /// every attached image are retained, and a failed image aborts the export.
    @concurrent static func render(_ document: PiliContentImageDocument) async throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PiliCapture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var pages: [URL] = []
        do {
            let text = "\(document.title) · \(document.author)\n\n\(document.text)\n\n\(document.source)"
            guard text.utf16.count <= 100_000, document.pictures.count <= 30 else { throw PiliOfflineError.message("内容过长，无法生成图片") }
            let style = NSMutableParagraphStyle(); style.lineSpacing = 10
            let string = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 30), .foregroundColor: UIColor.black, .paragraphStyle: style])
            let setter = CTFramesetterCreateWithAttributedString(string)
            var offset = 0
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1080, height: 1440), format: format)
            while offset < string.length {
                try Task.checkCancellation()
                let path = CGPath(rect: CGRect(x: 56, y: 84, width: 968, height: 1300), transform: nil)
                let frame = CTFramesetterCreateFrame(setter, CFRange(location: offset, length: 0), path, nil)
                let count = CTFrameGetVisibleStringRange(frame).length
                guard count > 0 else { throw PiliOfflineError.message("无法排版文字") }
                let file = directory.appendingPathComponent("page-\(pages.count + 1).png")
                try autoreleasepool {
                    let image = renderer.image { context in
                        UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1080, height: 1440))
                        context.cgContext.textMatrix = .identity
                        context.cgContext.translateBy(x: 0, y: 1440); context.cgContext.scaleBy(x: 1, y: -1)
                        CTFrameDraw(frame, context.cgContext)
                    }
                    guard let data = image.pngData() else { throw PiliOfflineError.message("图片编码失败") }
                    try data.write(to: file, options: .atomic)
                }
                pages.append(file); offset += count
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
            configuration.timeoutIntervalForRequest = 25
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            for raw in document.pictures {
                try Task.checkCancellation()
                guard let url = URL(string: raw.normalizedBiliURL()), url.scheme == "https" else { throw PiliOfflineError.message("图片地址无效") }
                var request = URLRequest(url: url); request.httpShouldHandleCookies = false
                request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
                let (downloaded, response) = try await session.download(for: request)
                defer { try? FileManager.default.removeItem(at: downloaded) }
                guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                      PiliOfflineStorage.size(downloaded) <= 40 * 1024 * 1024,
                      let source = CGImageSourceCreateWithURL(downloaded as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 2048, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
                    throw PiliOfflineError.message("附图下载或解码失败，请重试")
                }
                let file = directory.appendingPathComponent("page-\(pages.count + 1).png")
                try autoreleasepool {
                    let result = renderer.image { context in
                        UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1080, height: 1440))
                        (document.author as NSString).draw(in: CGRect(x: 56, y: 40, width: 968, height: 56), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 28), .foregroundColor: UIColor.black])
                        let scale = min(968 / Double(image.width), 1200 / Double(image.height))
                        let size = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
                        UIImage(cgImage: image).draw(in: CGRect(x: (1080 - size.width) / 2, y: 116, width: size.width, height: size.height))
                        (document.source as NSString).draw(in: CGRect(x: 56, y: 1350, width: 968, height: 50), withAttributes: [.font: UIFont.systemFont(ofSize: 22), .foregroundColor: UIColor.darkGray])
                    }
                    guard let data = result.pngData() else { throw PiliOfflineError.message("图片编码失败") }
                    try data.write(to: file, options: .atomic)
                }
                pages.append(file)
            }
            try Task.checkCancellation()
            return pages
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    static func save(_ files: [URL]) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw PiliOfflineError.message("请在系统设置中允许添加照片") }
        try await PHPhotoLibrary.shared().performChanges {
            for file in files { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: file) }
        }
    }
}
