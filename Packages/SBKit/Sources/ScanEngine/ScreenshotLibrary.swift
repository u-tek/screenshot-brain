import Core
import CoreGraphics
import Foundation
import ImageIO
import Photos
import Store
import UniformTypeIdentifiers

public enum PhotoAccess: String, Sendable {
    case full
    case limited
    case denied
    case notDetermined
}

/// The user's screenshots in the photo library.
public struct ScreenshotLibrary: Sendable {
    public enum LoadResult: Sendable {
        case image(CGImage)
        /// Only in iCloud right now; read it later rather than download during the first scan.
        case cloudOnly
        /// The asset is gone from the library.
        case missing
        /// The asset is there but couldn't be loaded this time (a failed request, an image that
        /// wouldn't decode, photo access not full). Left unread, to try again.
        case unavailable
    }

    public init() {}

    // MARK: Access

    public static func currentAccess() -> PhotoAccess {
        access(from: PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    public static func requestAccess() async -> PhotoAccess {
        access(from: await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    private static func access(from status: PHAuthorizationStatus) -> PhotoAccess {
        switch status {
        case .authorized: .full
        case .limited: .limited
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    // MARK: Discovery

    /// Screenshots created after `since`, newest first, leaving out the local identifiers in
    /// `known`. Metadata only, so it's fast.
    public func discover(since: Date?, skipping known: Set<String> = []) -> [DiscoveredScreenshot] {
        let options = PHFetchOptions()
        var predicates = [NSPredicate(format: "(mediaSubtypes & %d) != 0", Int32(PHAssetMediaSubtype.photoScreenshot.rawValue))]
        if let since {
            predicates.append(NSPredicate(format: "creationDate > %@", since as NSDate))
        }
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let result = PHAsset.fetchAssets(with: .image, options: options)
        var screenshots: [DiscoveredScreenshot] = []
        screenshots.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            guard !known.contains(asset.localIdentifier) else { return }
            screenshots.append(DiscoveredScreenshot(
                assetLocalID: asset.localIdentifier,
                cloudID: nil,
                createdAt: asset.creationDate ?? Date()
            ))
        }

        // Local identifiers change on a new phone; cloud identifiers map items across devices.
        let cloudIDs = cloudIdentifiers(for: screenshots.map(\.assetLocalID))
        for index in screenshots.indices {
            screenshots[index].cloudID = cloudIDs[screenshots[index].assetLocalID]
        }
        return screenshots
    }

    /// Cloud identifiers for local ones, for the assets that have one.
    public func cloudIdentifiers(for localIdentifiers: [String]) -> [String: String] {
        let candidates = localIdentifiers.filter { !$0.hasPrefix(AppGroup.sharedIdentifierPrefix) }
        guard !candidates.isEmpty else { return [:] }
        let mappings = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: candidates)
        var result: [String: String] = [:]
        for (localIdentifier, mapping) in mappings {
            if case .success(let cloudID) = mapping {
                result[localIdentifier] = cloudID.stringValue
            }
        }
        return result
    }

    /// Local identifiers that no longer exist in the library.
    public func missingIdentifiers(among identifiers: [String]) -> [String] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var present = Set<String>()
        result.enumerateObjects { asset, _, _ in present.insert(asset.localIdentifier) }
        return identifiers.filter { !present.contains($0) }
    }

    // MARK: Images

    /// Loads a screenshot downscaled by `scale` (about half resolution reads text reliably and is
    /// much faster). Downloads from iCloud only when `allowsNetwork` (the backfill pass).
    public func loadImage(localIdentifier: String, scale: Double = 0.5, allowsNetwork: Bool = false) async -> LoadResult {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
            // With full access, no asset means it was deleted. Without it (limited, or revoked), it
            // may only be out of sight, so it stays for next time.
            return PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized ? .missing : .unavailable
        }
        let maxPixelSize = max(Int(Double(max(asset.pixelWidth, asset.pixelHeight)) * scale), 320)
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = allowsNetwork
        options.deliveryMode = .highQualityFormat
        options.version = .current

        let response: (data: Data?, inCloud: Bool) = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                continuation.resume(returning: (data, inCloud))
            }
        }
        guard let data = response.data else {
            return response.inCloud ? .cloudOnly : .unavailable
        }
        guard let image = Self.downsample(data, maxPixelSize: maxPixelSize) else {
            return .unavailable
        }
        return .image(image)
    }

    /// Decodes straight to a smaller size, without ever holding the full-resolution bitmap.
    public static func downsample(_ data: Data, maxPixelSize: Int) -> CGImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: Deletion

    /// Deletes screenshots from the library. iOS shows its own confirmation; throws if the user
    /// declines.
    public func delete(localIdentifiers: [String]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
            PHAssetChangeRequest.deleteAssets(assets)
        }
    }
}

/// Small JPEG thumbnails in the App Group, for the widget (which can't afford to decode
/// full screenshots).
public enum Thumbnailer {
    public static let maxPixelSize = 360

    /// Writes a thumbnail and returns its file name, relative to `directory`. Written under a
    /// temporary name and renamed into place, so the widget never reads half a file.
    public static func write(_ image: CGImage, id: String, directory: URL) throws -> String {
        let fileName = "\(id).jpg"
        let small = downscaled(image, maxPixelSize: maxPixelSize) ?? image
        try writeJPEG(small, to: directory.appendingPathComponent(fileName), quality: 0.75)
        return fileName
    }

    /// Writes a JPEG to a dot-prefixed temporary file beside `url`, then renames it over `url`.
    static func writeJPEG(_ image: CGImage, to url: URL, quality: Double) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
        // rename(2) replaces an existing file in one step.
        guard rename(temporary.path, url.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    static func downscaled(_ image: CGImage, maxPixelSize: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxPixelSize else { return image }
        let scale = Double(maxPixelSize) / Double(longest)
        let width = max(Int(Double(image.width) * scale), 1)
        let height = max(Int(Double(image.height) * scale), 1)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
