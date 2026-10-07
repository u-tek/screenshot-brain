import Foundation

/// Identifiers and service keys injected at build time through Info.plist.
///
/// The values come from `Config/Shared.xcconfig` (and `Config/Local.xcconfig` when present).
/// An xcconfig variable that is left unset expands to an empty string, so empty values read as `nil`.
public struct AppConfiguration: Sendable, Equatable {
    public var appGroupIdentifier: String?
    public var cloudKitContainerIdentifier: String?
    public var telemetryDeckAppID: String?

    public init(appGroupIdentifier: String?, cloudKitContainerIdentifier: String?, telemetryDeckAppID: String?) {
        self.appGroupIdentifier = appGroupIdentifier
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
        self.telemetryDeckAppID = telemetryDeckAppID
    }

    public init(infoDictionary: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let raw = infoDictionary[key] as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        self.init(
            appGroupIdentifier: value(InfoKey.appGroup),
            cloudKitContainerIdentifier: value(InfoKey.cloudKitContainer),
            telemetryDeckAppID: value(InfoKey.telemetryDeckAppID)
        )
    }

    /// The configuration of the running app or extension.
    public static let main = AppConfiguration(infoDictionary: Bundle.main.infoDictionary ?? [:])

    enum InfoKey {
        static let appGroup = "SBAppGroupIdentifier"
        static let cloudKitContainer = "SBCloudKitContainerIdentifier"
        static let telemetryDeckAppID = "SBTelemetryDeckAppID"
    }
}
