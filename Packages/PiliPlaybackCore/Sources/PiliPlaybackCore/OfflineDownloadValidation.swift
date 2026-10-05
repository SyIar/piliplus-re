import Foundation

/// URLSession owns resumable-file assembly. Validate its finished file, never append response bytes ourselves.
public enum OfflineDownloadValidation {
    public enum Failure: Error, Equatable, LocalizedError {
        case response(Int), empty, unexpectedContent, invalidRange, incomplete(expected: Int64, actual: Int64)
        public var errorDescription: String? {
            switch self {
            case .response(let status): "下载服务器返回 HTTP \(status)，请重试以刷新地址"
            case .empty: "服务器返回了空文件"
            case .unexpectedContent: "服务器返回了网页或错误信息，未保存为媒体文件"
            case .invalidRange: "断点续传响应范围无效，请重新下载"
            case .incomplete(let expected, let actual): "文件不完整：应为 \(expected) 字节，实际 \(actual) 字节"
            }
        }
    }

    public static func validate(status: Int, mimeType: String?, contentLength: Int64,
                                contentRange: String?, contentEncoding: String?, fileSize: Int64) throws {
        guard status == 200 || status == 206 else { throw Failure.response(status) }
        guard fileSize > 0 else { throw Failure.empty }
        let mime = (mimeType ?? "").lowercased().split(separator: ";").first.map(String.init) ?? ""
        guard !mime.hasPrefix("text/"), !mime.contains("json"), !mime.contains("xml") else {
            throw Failure.unexpectedContent
        }
        if status == 206 {
            guard let range = contentRange?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
                  range.hasPrefix("bytes ") else { throw Failure.invalidRange }
            let fields = range.dropFirst(6).split(separator: "/", omittingEmptySubsequences: false)
            guard fields.count == 2, let total = Int64(fields[1]), total > 0 else { throw Failure.invalidRange }
            let offsets = fields[0].split(separator: "-", omittingEmptySubsequences: false)
            guard offsets.count == 2, let start = Int64(offsets[0]), let end = Int64(offsets[1]),
                  start >= 0, end >= start, end == total - 1 else { throw Failure.invalidRange }
            guard contentLength < 0 || contentLength == end - start + 1 else { throw Failure.invalidRange }
            guard fileSize == total else { throw Failure.incomplete(expected: total, actual: fileSize) }
        } else if contentLength >= 0 && (contentEncoding == nil || contentEncoding?.lowercased() == "identity") {
            guard fileSize == contentLength else { throw Failure.incomplete(expected: contentLength, actual: fileSize) }
        }
    }
}
