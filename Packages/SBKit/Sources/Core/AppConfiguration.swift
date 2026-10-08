import Foundation

/// Identifiers and service keys injected at build time through Info.plist.
///
/// The values come from `Config/Shared.xcconfig` (and `Config/Local.xcconfig` when present).
/// An xcconfig variable that is left unset expands to an empty string, so empty values read as `nil`.
public struct AppConfiguration: Sendable, Equatable {
    public var appGroupIdentifier: String?
    public var cloudKitContainerIdentifier: String?
    public var telemetryDeckAppID: String?
    /// Host of the Sign in with Apple token endpoint (see /server). The xcconfig holds only the
    /// host, because "//" starts a comment there.
    public var accountServerHost: String?
    public var revenueCatAPIKey: String?
    /// Where "Say hello" in Settings goes.
    public var supportEmail: String?
    /// The privacy policy, linked from the paywall and Settings.
    public var privacyPolicyURL: URL?
    /// Sideload test builds only: lets people continue without Sign in with Apple, which free
    /// Apple ID signing (AltStore) can't provide. Never set for the App Store.
    public var allowsLocalAccount: Bool

    public init(
        appGroupIdentifier: String?,
        cloudKitContainerIdentifier: String?,
        telemetryDeckAppID: String?,
        accountServerHost: String? = nil,
        revenueCatAPIKey: String? = nil,
        supportEmail: String? = nil,
        privacyPolicyURL: URL? = nil,
        allowsLocalAccount: Bool = false
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
        self.telemetryDeckAppID = telemetryDeckAppID
        self.accountServerHost = accountServerHost
        self.revenueCatAPIKey = revenueCatAPIKey
        self.supportEmail = supportEmail
        self.privacyPolicyURL = privacyPolicyURL
        self.allowsLocalAccount = allowsLocalAccount
    }

    public var accountServerURL: URL? {
        accountServerHost.flatMap { URL(string: "https://\($0)") }
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
            telemetryDeckAppID: value(InfoKey.telemetryDeckAppID),
            accountServerHost: value(InfoKey.accountServerHost),
            revenueCatAPIKey: value(InfoKey.revenueCatAPIKey),
            supportEmail: value(InfoKey.supportEmail),
            privacyPolicyURL: value(InfoKey.privacyPolicyURL).flatMap(URL.init(string:)),
            allowsLocalAccount: value(InfoKey.allowsLocalAccount).map { ["yes", "true", "1"].contains($0.lowercased()) } ?? false
        )
    }

    /// The configuration of the running app or extension.
    public static let main = AppConfiguration(infoDictionary: Bundle.main.infoDictionary ?? [:])

    enum InfoKey {
        static let appGroup = "SBAppGroupIdentifier"
        static let cloudKitContainer = "SBCloudKitContainerIdentifier"
        static let telemetryDeckAppID = "SBTelemetryDeckAppID"
        static let accountServerHost = "SBAccountServerHost"
        static let revenueCatAPIKey = "SBRevenueCatAPIKey"
        static let supportEmail = "SBSupportEmail"
        static let privacyPolicyURL = "SBPrivacyPolicyURL"
        static let allowsLocalAccount = "SBAllowsLocalAccount"
    }
}
