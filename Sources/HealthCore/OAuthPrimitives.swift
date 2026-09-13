import Foundation
import CryptoKit
import Security

public struct OAuthConfiguration: Codable {
    public struct Installed: Codable {
        public var client_id: String
        public var client_secret: String
        public var project_id: String
        public var redirect_uris: [String]
    }
    public var installed: Installed
    public static func read(_ data: Data) throws -> OAuthConfiguration {
        let config = try JSONDecoder().decode(OAuthConfiguration.self, from: data)
        guard config.installed.client_id.hasSuffix(".apps.googleusercontent.com"), !config.installed.client_secret.isEmpty,
              config.installed.redirect_uris.contains(where: { URL(string: $0)?.host == "localhost" || URL(string: $0)?.host == "127.0.0.1" }) else {
            throw OAuthError.message("Import a Google OAuth client JSON for a Desktop app, with a localhost redirect.")
        }
        return config
    }
}

public enum OAuthError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

public enum OAuthPKCE {
    public static let scopes = ["sleep", "health_metrics_and_measurements", "activity_and_fitness", "settings"].map {
        "https://www.googleapis.com/auth/googlehealth.\($0).readonly"
    }
    public static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw OAuthError.message("Could not generate secure sign-in parameters.")
        }
        return base64URL(Data(bytes))
    }
    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    public static func challenge(_ verifier: String) -> String { base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    public static func authorizationURL(clientID: String, redirect: String, verifier: String, state: String) -> URL {
        var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        url.queryItems = ["client_id": clientID, "redirect_uri": redirect, "response_type": "code",
                          "scope": scopes.joined(separator: " "), "access_type": "offline", "prompt": "consent",
                          "code_challenge": challenge(verifier), "code_challenge_method": "S256", "state": state]
            .sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return url.url!
    }
    public static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let value = fields.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&")
        return Data(value.utf8)
    }
    public static func callbackCode(url: URL, expectedState: String) throws -> String {
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard parts.filter({ $0.name == "state" }).count == 1,
              parts.first(where: { $0.name == "state" })?.value == expectedState else {
            throw OAuthError.message("Sign-in security check failed. Please reconnect.")
        }
        if parts.contains(where: { $0.name == "error" }) { throw OAuthError.message("Google sign-in was declined. You can reconnect whenever you're ready.") }
        guard parts.filter({ $0.name == "code" }).count == 1,
              let code = parts.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw OAuthError.message("Google did not return an authorization code.")
        }
        return code
    }
}
