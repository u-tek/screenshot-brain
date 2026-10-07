import Foundation
import ImageIO

/// Screenshots handed over through the share sheet, for people who said no to photo access.
///
/// The share extension only copies images into the App Group's inbox (it can't afford to read
/// them); the app reads them the next time it's open.
public enum SharedInbox {
    /// Copies an image into the inbox. The file name starts with when the screenshot was taken,
    /// so the app can date it without the photo library.
    public static func deposit(_ source: URL, configuration: AppConfiguration = .main) throws {
        let inbox = try AppGroup.directory(.inbox, configuration: configuration)
        let taken = captureDate(of: source) ?? Date()
        let fileExtension = source.pathExtension.isEmpty ? "img" : source.pathExtension.lowercased()
        let name = "\(Int(taken.timeIntervalSince1970))-\(UUID().uuidString).\(fileExtension)"
        try FileManager.default.copyItem(at: source, to: inbox.appendingPathComponent(name))
    }

    /// Writes picked image data into the inbox (the in-app picker, which needs no photo access).
    public static func deposit(data: Data, fileExtension: String = "img", configuration: AppConfiguration = .main) throws {
        let inbox = try AppGroup.directory(.inbox, configuration: configuration)
        let source = CGImageSourceCreateWithData(data as CFData, nil)
        let taken = source.flatMap { captureDate(of: $0) } ?? Date()
        let name = "\(Int(taken.timeIntervalSince1970))-\(UUID().uuidString).\(fileExtension)"
        try data.write(to: inbox.appendingPathComponent(name), options: .atomic)
    }

    /// Images waiting in the inbox, oldest first, with the date each was taken.
    public static func pending(configuration: AppConfiguration = .main) -> [(url: URL, takenAt: Date)] {
        guard let inbox = try? AppGroup.directory(.inbox, configuration: configuration),
              let files = try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
        else { return [] }
        return files
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map { url -> (url: URL, takenAt: Date) in
                let stamp = url.lastPathComponent.split(separator: "-").first.flatMap { TimeInterval($0) }
                return (url, stamp.map(Date.init(timeIntervalSince1970:)) ?? Date())
            }
            .sorted { $0.takenAt < $1.takenAt }
    }

    /// The moment the screenshot was taken, from its metadata, or the file's creation date.
    static func captureDate(of url: URL) -> Date? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let date = captureDate(of: source) {
            return date
        }
        let values = try? url.resourceValues(forKeys: [.creationDateKey])
        return values?.creationDate
    }

    static func captureDate(of source: CGImageSource) -> Date? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        let candidates: [(String?, String?)] = [
            (exif?[kCGImagePropertyExifDateTimeOriginal] as? String, exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String),
            (tiff?[kCGImagePropertyTIFFDateTime] as? String, exif?[kCGImagePropertyExifOffsetTime] as? String),
            (png?[kCGImagePropertyPNGCreationTime] as? String, nil),
        ]
        for (text, offset) in candidates {
            if let text, let date = parseMetadataDate(text, offset: offset) {
                return date
            }
        }
        return nil
    }

    /// Parses "2026:09:14 00:41:07", with an optional "+10:00" offset (local time without one).
    static func parseMetadataDate(_ text: String, offset: String?) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let offset, let zone = timeZone(fromOffset: offset) {
            formatter.timeZone = zone
        }
        if let date = formatter.date(from: text) {
            return date
        }
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return formatter.date(from: text)
    }

    private static func timeZone(fromOffset offset: String) -> TimeZone? {
        let parts = offset.dropFirst().split(separator: ":").compactMap { Int($0) }
        guard let sign = offset.first, sign == "+" || sign == "-", parts.count == 2 else { return nil }
        let seconds = (parts[0] * 3_600 + parts[1] * 60) * (sign == "-" ? -1 : 1)
        return TimeZone(secondsFromGMT: seconds)
    }
}
