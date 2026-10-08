import AuthenticationServices
import Core
import Foundation
import Security

/// The signed-in user. Sign in with Apple is required so progress can sync and survive a new phone.
struct Account: Codable, Hashable, Sendable {
    /// Apple's stable user identifier for this app.
    var userID: String
    /// Apple sends the name only on the first authorisation, so it's kept from then on.
    var givenName: String?
    /// From the server's token exchange; needed to revoke the token when the account is deleted.
    var refreshToken: String?
    /// Sideload test builds only: no Apple ID behind it, so nothing syncs or needs revoking.
    var isLocalOnly: Bool?
}

/// Keeps the account in the Keychain.
enum AccountStore {
    private static let service = "ScreenshotBrain.account"
    private static let key = "current"

    static func load() -> Account? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Account.self, from: data)
    }

    static func save(_ account: Account) {
        guard let data = try? JSONEncoder().encode(account) else { return }
        let match: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemUpdate(match as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insert = match
            insert.merge(attributes) { $1 }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    static func delete() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Whether Apple still considers the user signed in. Revoked or missing credentials sign out.
    static func isStillAuthorised(_ account: Account) async -> Bool {
        if account.isLocalOnly == true { return true }
        do {
            let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: account.userID)
            return state == .authorized
        } catch {
            // Offline or unknown: don't sign anyone out over a network blip.
            return true
        }
    }
}
