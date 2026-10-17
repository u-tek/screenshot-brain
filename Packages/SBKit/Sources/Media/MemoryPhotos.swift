import Core
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Photos added to things done, for the did-it log: copied into the App Group, sized down, so
/// they show whatever photo access the app has and whatever happens to the original.
public enum MemoryPhotos {
    /// `AssetImage` identifiers for memory photos use this prefix before the file name.
    public static let identifierPrefix = "memory:"
    /// The long side of a saved copy, in pixels: plenty for a full-width card on any iPhone.
    static let maxPixelSize = 2048

    public static func identifier(for name: String) -> String {
        identifierPrefix + name
    }

    /// Saves a photo's data (any format Image I/O reads, HEIC included) as a JPEG copy, with its
    /// orientation applied. Returns the file name.
    public static func save(_ data: Data, directory: URL? = nil) throws -> String {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw CocoaError(.fileReadCorruptFile) }
        let name = UUID().uuidString + ".jpg"
        let url = try (directory ?? AppGroup.directory(.memories)).appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return name
    }

    public static func remove(_ name: String) {
        guard let directory = try? AppGroup.directory(.memories) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    /// Deletes the copies nothing uses any more: left behind when something stops being done.
    public static func removeUnused(keeping names: Set<String>, directory: URL? = nil) {
        guard let directory = directory ?? (try? AppGroup.directory(.memories)),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for file in files where !names.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func image(_ identifier: String, maxPixelSize: Int) -> CGImage? {
        let name = String(identifier.dropFirst(identifierPrefix.count))
        guard let directory = try? AppGroup.directory(.memories),
              let source = CGImageSourceCreateWithURL(directory.appendingPathComponent(name) as CFURL, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
