import AppKit
import Foundation
import HealthCore

private struct GitHubRelease: Decodable {
    let tagName: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case notes = "body"
    }
}

@MainActor
final class UpdateChecker {
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/Texseractrum/air-stats/releases/latest")!
    private static let countedReleaseURL = "https://health.aidaniil.com/latest"
    /// The download path, not the landing page: an update dialog should hand over the disk image.
    private static let downloadURL = URL(string: "https://health.aidaniil.com/download")!
    private static let automaticCheckInterval: TimeInterval = 24 * 60 * 60
    private static let initialCheckDelay: TimeInterval = 8

    /// Why this check is being made, so the release service can count installs and
    /// daily use. Nothing else about the Mac or its readings is sent.
    private enum CheckKind: String { case install, daily, manual }

    private let defaults: UserDefaults
    private let session: URLSession
    private var scheduledTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var hasStarted = false

    var automaticallyChecksForUpdates: Bool {
        didSet {
            defaults.set(automaticallyChecksForUpdates, forKey: "automaticallyChecksForUpdates")
            guard hasStarted else { return }
            if automaticallyChecksForUpdates { scheduleAutomaticChecks() }
            else { scheduledTask?.cancel(); scheduledTask = nil }
        }
    }

    var sharesAnonymousUsage: Bool {
        didSet { defaults.set(sharesAnonymousUsage, forKey: "sharesAnonymousUsage") }
    }

    var installedVersionLabel: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return "Development build"
        }
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            return "\(version) (\(build))"
        }
        return version
    }

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        if defaults.object(forKey: "automaticallyChecksForUpdates") == nil {
            automaticallyChecksForUpdates = true
        } else {
            automaticallyChecksForUpdates = defaults.bool(forKey: "automaticallyChecksForUpdates")
        }
        if defaults.object(forKey: "sharesAnonymousUsage") == nil {
            sharesAnonymousUsage = true
        } else {
            sharesAnonymousUsage = defaults.bool(forKey: "sharesAnonymousUsage")
        }
    }

    func startAutomaticChecks() {
        guard !hasStarted else { return }
        hasStarted = true
        if automaticallyChecksForUpdates { scheduleAutomaticChecks() }
    }

    func checkForUpdates() {
        performCheck(userInitiated: true)
    }

    private func scheduleAutomaticChecks() {
        scheduledTask?.cancel()
        let lastCheck = defaults.object(forKey: "lastSuccessfulUpdateCheck") as? Date
        let elapsed = lastCheck.map { Date().timeIntervalSince($0) } ?? Self.automaticCheckInterval
        let firstDelay = max(Self.initialCheckDelay, Self.automaticCheckInterval - elapsed)
        scheduledTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(firstDelay)) }
            catch { return }
            while !Task.isCancelled {
                guard let self, self.automaticallyChecksForUpdates else { return }
                self.performCheck(userInitiated: false)
                do { try await Task.sleep(for: .seconds(Self.automaticCheckInterval)) }
                catch { return }
            }
        }
    }

    private func performCheck(userInitiated: Bool) {
        guard requestTask == nil else {
            if userInitiated { showMessage("Already checking for updates", detail: "Air Stats is contacting the release server.") }
            return
        }
        guard let installed = installedVersion else {
            if userInitiated { showMessage("Unable to check for updates", detail: "This development build does not have a valid version number.") }
            return
        }

        requestTask = Task { [weak self] in
            guard let self else { return }
            defer { self.requestTask = nil }
            let kind: CheckKind = self.defaults.bool(forKey: "hasReportedInstall")
                ? (userInitiated ? .manual : .daily)
                : .install
            do {
                let release = try await self.latestRelease(kind: kind, installed: installed)
                guard let available = ReleaseVersion(release.tagName) else {
                    throw UpdateError.invalidRelease
                }
                self.defaults.set(Date(), forKey: "lastSuccessfulUpdateCheck")
                self.defaults.set(true, forKey: "hasReportedInstall")
                if available > installed {
                    let skipped = self.defaults.string(forKey: "skippedUpdateVersion")
                    if userInitiated || skipped != available.description {
                        self.showAvailableUpdate(release, available: available, installed: installed)
                    }
                } else if userInitiated {
                    self.showMessage("Air Stats is up to date", detail: "You’re using the latest version (\(installed)).")
                }
            } catch {
                if userInitiated {
                    self.showMessage("Unable to check for updates", detail: "Check your internet connection and try again.")
                }
            }
        }
    }

    private var installedVersion: ReleaseVersion? {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return nil }
        return ReleaseVersion(value)
    }

    /// The release service on health.aidaniil.com answers with the same public release
    /// and counts the request, which is how the project knows how many installs exist.
    /// Opting out asks GitHub directly instead, so no request reaches the project at all.
    private func releaseURL(kind: CheckKind, installed: ReleaseVersion) -> URL {
        guard sharesAnonymousUsage, var components = URLComponents(string: Self.countedReleaseURL) else {
            return Self.latestReleaseURL
        }
        let system = ProcessInfo.processInfo.operatingSystemVersion
        components.queryItems = [
            URLQueryItem(name: "k", value: kind.rawValue),
            URLQueryItem(name: "v", value: installed.description),
            URLQueryItem(name: "os", value: "\(system.majorVersion).\(system.minorVersion)")
        ]
        return components.url ?? Self.latestReleaseURL
    }

    private func latestRelease(kind: CheckKind, installed: ReleaseVersion) async throws -> GitHubRelease {
        var request = URLRequest(url: releaseURL(kind: kind, installed: installed))
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AirStats/\(installedVersionLabel)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badResponse
        }
        guard data.count <= 1_000_000 else { throw UpdateError.badResponse }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func showAvailableUpdate(_ release: GitHubRelease, available: ReleaseVersion, installed: ReleaseVersion) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Air Stats \(available) is available"
        var detail = "You’re using version \(installed). Download the new release, then replace Air Stats in your Applications folder."
        if let notes = release.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            let excerpt = String(notes.prefix(700)) + (notes.count > 700 ? "…" : "")
            detail += "\n\nWhat’s new:\n\(excerpt)"
        }
        alert.informativeText = detail
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "Remind Me Later")
        alert.addButton(withTitle: "Skip This Version")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(Self.downloadURL)
        case .alertThirdButtonReturn:
            defaults.set(available.description, forKey: "skippedUpdateVersion")
        default:
            break
        }
    }

    private func showMessage(_ title: String, detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private enum UpdateError: Error { case badResponse, invalidRelease }
}
