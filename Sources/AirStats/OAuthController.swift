import AppKit
import Combine
import Foundation
import HealthCore
import Network

private struct GoogleTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiry: Date
}

@MainActor
final class OAuthController: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isSigningIn = false
    @Published private(set) var configuration: OAuthConfiguration?
    @Published var error: String?
    private var tokens: GoogleTokens?
    private var server: LoopbackServer?
    private var signInTask: Task<Void, Never>?
    private var generation = UUID()
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()
    private var tokenAccount: String { "tokens.\(configuration?.installed.client_id ?? "")" }

    init(loadStored: Bool = true) {
        guard loadStored else { return }
        do {
            // A user-imported client (Keychain) always wins; otherwise fall back to the
            // client bundled with the app so people can connect without importing a JSON.
            if let data = try Keychain.read("oauth.configuration") { configuration = try OAuthConfiguration.read(data) }
            else { configuration = Self.bundledConfiguration() }
            if configuration != nil, let data = try Keychain.read(tokenAccount) {
                tokens = try JSONDecoder().decode(GoogleTokens.self, from: data)
                isConnected = tokens != nil
            }
        } catch { self.error = error.localizedDescription }
    }

    /// The OAuth client shipped inside the app bundle, if present and valid.
    /// Injected at build time (see scripts/build.sh); absent builds simply require an import.
    static func bundledConfiguration() -> OAuthConfiguration? {
        guard let url = Bundle.main.url(forResource: "DefaultOAuth", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? OAuthConfiguration.read(data)
    }
    func importConfiguration(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        let nextConfiguration = try OAuthConfiguration.read(data)
        cancelSignIn()
        if let previousClientID = configuration?.installed.client_id,
           previousClientID != nextConfiguration.installed.client_id {
            try Keychain.delete("tokens.\(previousClientID)")
        }
        try Keychain.save(data, account: "oauth.configuration")
        configuration = nextConfiguration
        tokens = nil
        isConnected = false
        if let data = try Keychain.read(tokenAccount) {
            tokens = try JSONDecoder().decode(GoogleTokens.self, from: data)
            isConnected = tokens != nil
        }
        error = nil
    }
    func connect() {
        guard !isSigningIn else { return }
        guard let configuration else { error = "Import your Google Desktop OAuth JSON to connect."; return }
        error = nil
        isSigningIn = true
        let current = UUID()
        generation = current
        signInTask = Task {
            do {
                let state = try OAuthPKCE.random(), verifier = try OAuthPKCE.random()
                let server = LoopbackServer(state: state)
                self.server = server
                let redirect = try await server.start()
                let url = OAuthPKCE.authorizationURL(clientID: configuration.installed.client_id,
                                                     redirect: redirect, verifier: verifier, state: state)
                let code = try await server.authorize(url)
                let response = try await tokenRequest(["client_id": configuration.installed.client_id,
                                                       "client_secret": configuration.installed.client_secret,
                                                       "grant_type": "authorization_code", "code": code,
                                                       "redirect_uri": redirect, "code_verifier": verifier])
                try Task.checkCancellation()
                guard generation == current else { return }
                try saveTokens(response, previousRefresh: nil)
                isConnected = true
            } catch {
                if generation == current, !(error is CancellationError) { self.error = error.localizedDescription }
            }
            if generation == current {
                self.server?.stop()
                self.server = nil
                self.isSigningIn = false
            }
        }
    }
    func cancelSignIn() {
        generation = UUID()
        signInTask?.cancel()
        signInTask = nil
        server?.stop()
        server = nil
        isSigningIn = false
    }
    func accessToken() async throws -> String {
        guard let tokens, let configuration else { throw OAuthError.message("Connect your Google account first.") }
        if tokens.expiry.timeIntervalSinceNow > 60 { return tokens.accessToken }
        let current = generation
        let response = try await tokenRequest(["client_id": configuration.installed.client_id,
                                               "client_secret": configuration.installed.client_secret,
                                               "grant_type": "refresh_token", "refresh_token": tokens.refreshToken])
        try Task.checkCancellation()
        guard current == generation else { throw CancellationError() }
        try saveTokens(response, previousRefresh: tokens.refreshToken)
        return self.tokens!.accessToken
    }
    func disconnect() throws {
        cancelSignIn()
        // Remove tokens left by any previously imported OAuth client as well as the active one.
        try Keychain.deleteAccounts(prefix: "tokens.")
        tokens = nil
        isConnected = false
        error = nil
    }
    private func tokenRequest(_ fields: [String: String]) async throws -> JSONValue {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OAuthPKCE.form(fields)
        let (data, response) = try await session.data(for: request)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            if json["error"].string == "invalid_grant" {
                error = "Google authorization expired or was revoked. Reconnect your account. Test-mode access expires after 7 days."
                isConnected = false
                throw OAuthError.message(error!)
            }
            throw OAuthError.message("Google couldn't complete sign-in. Check your OAuth client and try reconnecting.")
        }
        return json
    }
    private func saveTokens(_ response: JSONValue, previousRefresh: String?) throws {
        guard let access = response["access_token"].string,
              let refresh = response["refresh_token"].string ?? previousRefresh else {
            throw OAuthError.message("Google didn't grant offline access. Reconnect and allow the requested permissions.")
        }
        let next = GoogleTokens(accessToken: access, refreshToken: refresh,
                                expiry: Date().addingTimeInterval(response["expires_in"].number ?? 3600))
        try Keychain.save(try JSONEncoder().encode(next), account: tokenAccount)
        tokens = next
    }
}

/// Desktop OAuth redirects are accepted only on an ephemeral loopback socket.
@MainActor
private final class LoopbackServer {
    private let state: String
    private var listener: NWListener?
    private var ready: CheckedContinuation<String, Error>?
    private var code: CheckedContinuation<String, Error>?
    private var timeout: Task<Void, Never>?
    private var redirect: String = ""
    init(state: String) { self.state = state }

    func start() async throws -> String {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.receive(connection) }
        }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(240))
            guard !Task.isCancelled else { return }
            self?.stop(error: OAuthError.message("Sign-in timed out. Click Connect to try again."))
        }
        return try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            listener.stateUpdateHandler = { [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    switch status {
                    case .ready:
                        guard let port = listener.port else { return }
                        self.redirect = "http://127.0.0.1:\(port.rawValue)/oauth/callback"
                        self.ready?.resume(returning: self.redirect); self.ready = nil
                    case .failed(let error): self.stop(error: error)
                    default: break
                    }
                }
            }
            listener.start(queue: .main)
        }
    }
    func authorize(_ url: URL) async throws -> String {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            code = continuation
            if !NSWorkspace.shared.open(url) { stop(error: OAuthError.message("Couldn't open your browser. Try connecting again.")) }
        }
    }
    func stop(error: Error = CancellationError()) {
        ready?.resume(throwing: error); ready = nil
        code?.resume(throwing: error); code = nil
        timeout?.cancel(); timeout = nil
        listener?.cancel(); listener = nil
    }
    private func receive(_ connection: NWConnection, buffer: Data = Data()) {
        if buffer.isEmpty { connection.start(queue: .main) }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] chunk, _, complete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                var data = buffer
                if let chunk { data.append(chunk) }
                guard data.count <= 16384 else { connection.cancel(); return }
                if !data.containsHTTPHeaderEnd {
                    if complete || error != nil { connection.cancel() } else { self.receive(connection, buffer: data) }
                    return
                }
                guard let request = String(data: data, encoding: .utf8),
                      let line = request.components(separatedBy: "\r\n").first else { connection.cancel(); return }
                let parts = line.split(separator: " ")
                guard parts.count == 3, parts[0] == "GET", parts[1].hasPrefix("/oauth/callback?"),
                      let base = URLComponents(string: self.redirect),
                      let url = URL(string: "http://127.0.0.1:\(base.port!)\(parts[1])") else {
                    self.respond(connection, status: "404 Not Found", message: "This address is only used for Air Stats sign-in.")
                    return
                }
                do {
                    let value = try OAuthPKCE.callbackCode(url: url, expectedState: self.state)
                    self.respond(connection, status: "200 OK", message: "Google authorization received. Return to Air Stats to finish connecting. You can close this tab.")
                    self.code?.resume(returning: value); self.code = nil
                    self.timeout?.cancel()
                    self.listener?.cancel()
                } catch {
                    self.respond(connection, status: "400 Bad Request", message: "Sign-in could not be completed. Return to Air Stats and try again.")
                    // A stray invalid request must not cancel a legitimate in-progress sign-in.
                    let suppliedState = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "state" })?.value
                    if suppliedState == self.state { self.stop(error: error) }
                }
            }
        }
    }
    private func respond(_ connection: NWConnection, status: String, message: String) {
        let html = "<!doctype html><meta charset='utf-8'><title>Air Stats</title><body style='background:#12221f;color:#e9f6ef;font:18px system-ui;max-width:480px;margin:15vh auto;padding:24px'><h1>Air Stats</h1><p>\(message)</p>"
        let data = Data(html.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(data.count)\r\nConnection: close\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'; style-src 'unsafe-inline'\r\n\r\n"
        connection.send(content: Data(header.utf8) + data, completion: .contentProcessed { _ in connection.cancel() })
    }
}

private extension Data {
    var containsHTTPHeaderEnd: Bool { range(of: Data("\r\n\r\n".utf8)) != nil }
}
