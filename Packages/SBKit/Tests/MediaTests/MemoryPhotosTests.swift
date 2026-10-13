import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Media

@Suite struct MemoryPhotosTests {
    /// A small solid-colour PNG, standing in for a photo the user picked.
    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(red: 0.91, green: 0.27, blue: 0.55, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func savingAPhotoWritesAJPEGCopyAndReturnsItsName() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try pngData(width: 64, height: 48)

        let name = try MemoryPhotos.save(data, directory: directory)

        #expect(name.hasSuffix(".jpg"))
        let url = directory.appendingPathComponent(name)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let format = try #require(CGImageSourceGetType(source))
        #expect((format as String) == UTType.jpeg.identifier)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width > 0)
        #expect(image.height > 0)
    }

    @Test func savingSomethingThatIsNotAnImageThrowsAndWritesNothing() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: CocoaError.self) {
            _ = try MemoryPhotos.save(Data("not a photo".utf8), directory: directory)
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.isEmpty)
    }

    @Test func clearingUpKeepsOnlyThePhotosStillInUse() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let kept = try MemoryPhotos.save(try pngData(width: 8, height: 8), directory: directory)
        _ = try MemoryPhotos.save(try pngData(width: 8, height: 8), directory: directory)

        MemoryPhotos.removeUnused(keeping: [kept], directory: directory)

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files == [kept])
    }
}
