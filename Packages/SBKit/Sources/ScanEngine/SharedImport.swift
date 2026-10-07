import Core
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Store
import UniformTypeIdentifiers

extension ScanPipeline {
    /// The longest side of the copy kept for display. Shared screenshots have no library asset,
    /// so this copy is the only one the app has.
    static let sharedDisplaySize = 1_600

    /// Reads every image the share extension left in the inbox, the same way as library
    /// screenshots. Returns how many new screenshots were added.
    @discardableResult
    public func importShared(
        configuration: AppConfiguration = .main,
        now: Date = Date(),
        progress: @Sendable (ScanProgress) -> Void = { _ in }
    ) async throws -> Int {
        let pending = SharedInbox.pending(configuration: configuration)
        guard !pending.isEmpty else { return 0 }
        let keep = try AppGroup.directory(.shared, configuration: configuration)
        progress(ScanProgress(read: 0, total: pending.count))

        var added: [ScreenshotItem] = []
        for (index, file) in pending.enumerated() {
            try Task.checkCancellation()
            defer {
                try? FileManager.default.removeItem(at: file.url)
                progress(ScanProgress(read: index + 1, total: pending.count))
            }
            guard let data = try? Data(contentsOf: file.url) else { continue }
            // Sharing the same screenshot twice shouldn't count it twice.
            let digest = SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
            let identifier = AppGroup.sharedIdentifierPrefix + digest
            guard try !database.containsItem(assetLocalID: identifier) else { continue }
            guard let image = Self.halfResolution(data) else { continue }

            let item = ScreenshotItem(assetLocalID: identifier, createdAt: file.takenAt, updatedAt: now)
            let read = await analyse(item, image: image, now: now)
            // A flagged image is never kept: nothing could ever show it.
            if !read.isNSFWFlagged, let display = ScreenshotLibrary.downsample(data, maxPixelSize: Self.sharedDisplaySize) {
                try? Self.writeJPEG(display, to: keep.appendingPathComponent("\(digest).jpg"))
            }
            try database.save([read])
            added.append(read)
        }
        try groupNearDuplicates(added)
        return added.count
    }

    /// About half resolution, like library screenshots.
    static func halfResolution(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return ScreenshotLibrary.downsample(data, maxPixelSize: max(max(width, height) / 2, 320))
    }

    static func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
