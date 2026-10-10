import CoreGraphics
import SwiftUI
import Testing
@testable import Media

@MainActor
@Suite struct FittedImageTests {
    private func image(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    /// Renders an image into a 120 by 260 slot and returns the size it took.
    private func renderedSize(width: Int, height: Int) throws -> (width: Int, height: Int) {
        let renderer = ImageRenderer(content: FittedImage(image: try image(width: width, height: height)))
        renderer.proposedSize = ProposedViewSize(width: 120, height: 260)
        renderer.scale = 1
        let rendered = try #require(renderer.cgImage)
        return (rendered.width, rendered.height)
    }

    /// A wide image in a tall slot is cropped to the slot instead of growing it (which laid whole
    /// screens out zoomed in).
    @Test func aWideImageStaysInItsSlot() throws {
        let size = try renderedSize(width: 2400, height: 1000)
        #expect(size.width == 120)
        #expect(size.height == 260)
    }

    /// So is a scrolling screenshot, far taller than its slot.
    @Test func aTallImageStaysInItsSlot() throws {
        let size = try renderedSize(width: 1000, height: 8000)
        #expect(size.width == 120)
        #expect(size.height == 260)
    }

    /// Why FittedImage exists: the way screenshots used to be drawn, a filled image in a ZStack,
    /// reports the image's size, so a wide screenshot made its whole screen wider than the phone.
    @Test func aFilledImageInAStackGrowsPastItsSlot() throws {
        let wide = try image(width: 2400, height: 1000)
        let renderer = ImageRenderer(content: ZStack {
            Color.clear
            Image(decorative: wide, scale: 1).resizable().aspectRatio(contentMode: .fill)
        })
        renderer.proposedSize = ProposedViewSize(width: 120, height: 260)
        renderer.scale = 1
        let rendered = try #require(renderer.cgImage)
        #expect(rendered.width > 120)
    }
}
