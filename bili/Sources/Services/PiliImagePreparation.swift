import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum PiliImagePreparation {
    /// Decode only the pixels needed by the editor/upload. UIImage(data:)
    /// followed by jpegData can expand a 48 MP photograph in full first.
    static func jpeg(_ data: Data, maxPixelSize: Int = 2560) async -> Data? {
        guard !data.isEmpty, data.count <= 40 * 1024 * 1024, (64...4096).contains(maxPixelSize) else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> Data? in
            autoreleasepool {
                guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { return nil }
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
                CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
                guard CGImageDestinationFinalize(destination), output.length <= 10 * 1024 * 1024 else { return nil }
                return output as Data
            }
        }.value
    }
}
