import Core
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Photos
import SwiftUI

/// Loads screenshots from the photo library for display in the app.
public enum AssetImageLoader {
    /// Stand-in screenshots by identifier, for design snapshots: their sample items have no
    /// photos, so without these every card and tile would render empty. Never set in the app.
    nonisolated(unsafe) public static var samples: [String: CGImage] = [:]

    /// Decoded straight to `maxPixelSize`, with the asset's orientation applied. May fetch from
    /// iCloud when `allowsNetwork` is true (for the item detail screen, never during a scan).
    public static func image(localIdentifier: String, maxPixelSize: Int, allowsNetwork: Bool = false) async -> CGImage? {
        if let sample = samples[localIdentifier] {
            return sample
        }
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

    private nonisolated(unsafe) static let blurContext = CIContext()

    /// The image and, with `backdrop`, its soft wash, both worked out off the main thread.
    public static func image(localIdentifier: String, maxPixelSize: Int, allowsNetwork: Bool, backdrop: Bool) async -> (image: CGImage?, backdrop: CGImage?) {
        let image = await self.image(localIdentifier: localIdentifier, maxPixelSize: maxPixelSize, allowsNetwork: allowsNetwork)
        guard backdrop, let image else { return (image, nil) }
        return (image, wash(of: image))
    }

    /// A soft wash of an image's own colours: shrunk to a few dozen pixels and blurred, once,
    /// here. Drawn large behind the whole screenshot it fills the rest of a card, and nothing
    /// re-blurs as the card moves.
    static func wash(of image: CGImage) -> CGImage? {
        let width = 32
        let height = max(1, Int((Double(image.height) / Double(max(image.width, 1)) * Double(width)).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let small = context.makeImage() else { return nil }
        let input = CIImage(cgImage: small)
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 2.5).cropped(to: input.extent)
        return blurContext.createCGImage(blurred, from: input.extent) ?? small
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

/// A screenshot from the library in its frame: filling it (cropped), or whole over a soft wash of
/// its own colours. Shows nothing until it has loaded.
public struct AssetImage: View {
    private let localIdentifier: String
    private let maxPixelSize: Int
    private let allowsNetwork: Bool
    private let contentMode: ContentMode
    private let alignment: Alignment
    private let showsBackdrop: Bool
    private let insets: EdgeInsets
    private let cornerRadius: CGFloat
    @State private var image: CGImage?
    @State private var backdrop: CGImage?

    /// - Parameters:
    ///   - alignment: Which part of the screenshot stays in view when it's cropped to fill.
    ///   - backdrop: Fills the frame with a soft wash of the screenshot's colours, for `.fit`.
    ///   - insets: Room around the screenshot inside the frame (the backdrop still fills it).
    ///   - cornerRadius: Rounds the screenshot's own corners.
    public init(
        _ localIdentifier: String,
        maxPixelSize: Int = 600,
        allowsNetwork: Bool = false,
        contentMode: ContentMode = .fill,
        alignment: Alignment = .center,
        backdrop: Bool = false,
        insets: EdgeInsets = EdgeInsets(),
        cornerRadius: CGFloat = 0
    ) {
        self.localIdentifier = localIdentifier
        self.maxPixelSize = maxPixelSize
        self.allowsNetwork = allowsNetwork
        self.contentMode = contentMode
        self.alignment = alignment
        self.showsBackdrop = backdrop
        self.insets = insets
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        FittedImage(image: image, contentMode: contentMode, alignment: alignment, backdrop: backdrop, insets: insets, cornerRadius: cornerRadius)
            .task(id: localIdentifier) {
                let loaded = await AssetImageLoader.image(
                    localIdentifier: localIdentifier, maxPixelSize: maxPixelSize, allowsNetwork: allowsNetwork, backdrop: showsBackdrop
                )
                withAnimation(.easeOut(duration: 0.25)) {
                    image = loaded.image
                    backdrop = loaded.backdrop
                }
            }
            .accessibilityHidden(true)
    }
}

/// An image that takes exactly the space it's offered, cropped to it when filling.
///
/// A filled image reports the size it grew to, not the size it was offered. In a ZStack that
/// made the stack, and every frame around it, as big as the image: a screenshot whose shape
/// didn't match its card laid the whole screen out several times too large, so all that showed
/// was a corner of the light, zoomed in. An overlay on a clear base can't do that.
struct FittedImage: View {
    let image: CGImage?
    var contentMode: ContentMode = .fill
    var alignment: Alignment = .center
    /// A soft wash of the image's colours, filling the whole frame behind it.
    var backdrop: CGImage?
    var insets = EdgeInsets()
    var cornerRadius: CGFloat = 0

    var body: some View {
        // The clear base takes the space it's offered even before (or without) an image, so
        // whatever sits behind it, like a placeholder light, still shows.
        Color.clear
            .overlay {
                if let backdrop {
                    Image(decorative: backdrop, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .overlay(Color.black.opacity(0.3))
                        .transition(.opacity)
                }
            }
            .overlay(alignment: alignment) {
                if let image {
                    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .clipShape(shape)
                        .overlay {
                            if cornerRadius > 0 {
                                shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                            }
                        }
                        .padding(insets)
                        .transition(.opacity)
                }
            }
            .clipped()
    }
}

/// A thumbnail written by the scan engine into the App Group (the widget's source).
public struct ThumbnailImage: View {
    private let url: URL?

    public init(url: URL?) {
        self.url = url
    }

    public var body: some View {
        let image = url
            .flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
            .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        FittedImage(image: image)
    }
}
