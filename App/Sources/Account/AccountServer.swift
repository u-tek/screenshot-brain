import Core
import Foundation

/// The small serverless endpoint in /server. Apple requires apps that offer Sign in with Apple to
/// revoke the user's token when they delete their account; that needs the app's private key, so
/// it can't happen on the device.
enum AccountServer {
    struct TokenResponse: Decodable {
        let refreshToken: String

        enum CodingKeys: String, CodingKey {
            case refreshToken = "refresh_token"
        }
    }

    /// Exchanges the one-time authorisation code (valid for five minutes) for a refresh token.
    static func exchange(authorizationCode: String, configuration: AppConfiguration = .main) async -> String? {
        guard let base = configuration.accountServerURL else {
            Log.app.notice("No account server configured; token revocation won't be possible for this sign-in.")
            return nil
        }
        do {
            let data = try await post(base.appendingPathComponent("token"), body: ["code": authorizationCode])
            return try JSONDecoder().decode(TokenResponse.self, from: data).refreshToken
        } catch {
            Log.app.error("Token exchange failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Revokes the user's Sign in with Apple token.
    static func revoke(refreshToken: String, configuration: AppConfiguration = .main) async throws {
        guard let base = configuration.accountServerURL else { throw URLError(.badURL) }
        _ = try await post(base.appendingPathComponent("revoke"), body: ["refresh_token": refreshToken])
    }

    private static func post(_ url: URL, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
