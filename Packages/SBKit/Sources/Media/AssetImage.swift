import Core
import CoreGraphics
import Foundation
import ImageIO
import Photos
import SwiftUI

/// Loads screenshots from the photo library for display in the app.
public enum AssetImageLoader {
    /// Decoded straight to `maxPixelSize`, with the asset's orientation applied. May fetch from
    /// iCloud when `allowsNetwork` is true (for the item detail screen, never during a scan).
    public static func image(localIdentifier: String, maxPixelSize: Int, allowsNetwork: Bool = false) async -> CGImage? {
        if localIdentifier.hasPrefix(AppGroup.sharedIdentifierPrefix) {
            return sharedImage(localIdentifier, maxPixelSize: maxPixelSize)
        }
        // Touching the library without access makes iOS show its permission prompt. Only the
        // app's own pre-prompt may do that, so images just don't load until access is granted.
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = allowsNetwork
        options.deliveryMode = .highQualityFormat
        options.version = .current
        let data: Data? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data else { return nil }
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else { return nil }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
    }

    /// A screenshot shared in without photo access, from the app's own copy.
    private static func sharedImage(_ identifier: String, maxPixelSize: Int) -> CGImage? {
        let name = identifier.dropFirst(AppGroup.sharedIdentifierPrefix.count) + ".jpg"
        guard let directory = try? AppGroup.directory(.shared),
              let source = CGImageSourceCreateWithURL(directory.appendingPathComponent(String(name)) as CFURL, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// A screenshot from the library, filling its frame. Shows nothing until it has loaded.
public struct AssetImage: View {
    private let localIdentifier: String
    private let maxPixelSize: Int
    private let allowsNetwork: Bool
    private let contentMode: ContentMode
    @State private var image: CGImage?
    @Environment(\.displayScale) private var displayScale

    public init(_ localIdentifier: String, maxPixelSize: Int = 600, allowsNetwork: Bool = false, contentMode: ContentMode = .fill) {
        self.localIdentifier = localIdentifier
        self.maxPixelSize = maxPixelSize
        self.allowsNetwork = allowsNetwork
        self.contentMode = contentMode
    }

    public var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .task(id: localIdentifier) {
            let loaded = await AssetImageLoader.image(localIdentifier: localIdentifier, maxPixelSize: maxPixelSize, allowsNetwork: allowsNetwork)
            withAnimation(.easeOut(duration: 0.25)) {
                image = loaded
            }
        }
        .accessibilityHidden(true)
    }
}

/// A thumbnail written by the scan engine into the App Group (the widget's source).
public struct ThumbnailImage: View {
    private let url: URL?

    public init(url: URL?) {
        self.url = url
    }

    public var body: some View {
        if let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color.clear
        }
    }
}
