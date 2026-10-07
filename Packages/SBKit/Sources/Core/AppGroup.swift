import Foundation

/// The container shared by the app, the widget and the share extension.
public enum AppGroup {
    public enum Directory: String, CaseIterable, Sendable {
        case database = "Database"
        /// Small pre-rendered thumbnails the widget can afford to load.
        case thumbnails = "Thumbnails"
        /// Pre-rendered light images for the widget, which can't run shaders.
        case widgetLight = "WidgetLight"
        /// Images handed over by the share extension, waiting for the app to read them.
        case inbox = "Inbox"
        /// Screenshots shared in without photo access. The app's only copy, since there's no
        /// library asset to load them from.
        case shared = "Shared"
    }

    /// Items made from shared images use this prefix in place of a photo library identifier.
    public static let sharedIdentifierPrefix = "shared:"

    /// Root of the shared container.
    ///
    /// Falls back to Application Support when the App Group entitlement is missing (an unsigned
    /// simulator build), so the app still runs; extensions won't see the data in that case.
    public static func containerURL(configuration: AppConfiguration = .main) -> URL {
        let fileManager = FileManager.default
        if let identifier = configuration.appGroupIdentifier,
           let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        Log.app.error("App Group container unavailable; using Application Support. Extensions won't see shared data.")
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Returns a directory inside the shared container, creating it if needed.
    ///
    /// Every directory is excluded from device backups: screenshots and their extracted text never
    /// leave the device, and everything here can be rebuilt by rescanning. Progress is restored
    /// through CloudKit metadata sync instead.
    public static func directory(_ directory: Directory, configuration: AppConfiguration = .main) throws -> URL {
        var url = containerURL(configuration: configuration)
            .appendingPathComponent(directory.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        return url
    }
}
