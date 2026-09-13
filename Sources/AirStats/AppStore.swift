import AppKit
import Combine
import HealthCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum DashboardTab: String, CaseIterable { case overview = "Overview", sleep = "Sleep", vitals = "Vitals", settings = "Settings" }

@MainActor
final class AppStore: ObservableObject {
    @Published var snapshot = HealthSnapshot()
    @Published var tab: DashboardTab = .overview
    @Published var isRefreshing = false
    @Published var isDemo = false
    @Published var error: String?
    @Published var now = Date()
    @Published var refreshInterval: Double { didSet { defaults.set(refreshInterval, forKey: "refreshInterval") } }
    @Published var showHeart: Bool { didSet { defaults.set(showHeart, forKey: "showHeart") } }
    @Published var showSleep: Bool { didSet { defaults.set(showSleep, forKey: "showSleep") } }
    @Published var showSteps: Bool { didSet { defaults.set(showSteps, forKey: "showSteps") } }
    @Published var showHRV: Bool { didSet { defaults.set(showHRV, forKey: "showHRV") } }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    let auth: OAuthController
    private let client = HealthClient()
    private let defaults: UserDefaults
    private var subscriptions = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private var generation = UUID()
    private var nextRefresh = Date.distantPast
    var isConnected: Bool { auth.isConnected }
    var hasConfiguration: Bool { auth.configuration != nil }

    init(preview: Bool = false) {
        defaults = preview ? UserDefaults(suiteName: "dev.sparkles.airstats.preview")! : .standard
        refreshInterval = defaults.object(forKey: "refreshInterval") as? Double ?? 300
        showHeart = defaults.object(forKey: "showHeart") as? Bool ?? true
        showSleep = defaults.object(forKey: "showSleep") as? Bool ?? true
        showSteps = defaults.bool(forKey: "showSteps")
        showHRV = defaults.bool(forKey: "showHRV")
        auth = OAuthController(loadStored: !preview)
        auth.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }.store(in: &subscriptions)
        auth.$isConnected.removeDuplicates().dropFirst().sink { [weak self] connected in
            guard let self else { return }
            DispatchQueue.main.async {
                self.clearReadings()
                self.isDemo = false
                if connected { self.refresh() }
            }
        }.store(in: &subscriptions)
        if !preview {
            Timer.publish(every: 15, on: .main, in: .common).autoconnect().sink { [weak self] date in
                guard let self else { return }
                self.now = date
                if date >= self.nextRefresh { self.refresh() }
            }.store(in: &subscriptions)
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }.store(in: &subscriptions)
        }
    }
    func refresh() {
        guard isConnected, !isDemo, !isRefreshing else { return }
        isRefreshing = true
        error = nil
        nextRefresh = Date().addingTimeInterval(max(60, refreshInterval))
        let current = generation
        refreshTask = Task {
            do {
                let token = try await auth.accessToken()
                let result = try await client.snapshot(token: token)
                try Task.checkCancellation()
                guard current == generation else { return }
                snapshot = result
                now = Date()
                if result.issues.count == HealthQuery.types.count + 1 {
                    error = "Couldn't refresh your data. Open Settings for details."
                }
                if result.issues.values.contains(where: { $0.contains("request limit") }) {
                    nextRefresh = Date().addingTimeInterval(max(900, refreshInterval))
                }
            } catch {
                if current == generation, !(error is CancellationError) { self.error = error.localizedDescription }
            }
            if current == generation { isRefreshing = false }
        }
    }
    func clearReadings() {
        generation = UUID()
        refreshTask?.cancel(); refreshTask = nil
        isRefreshing = false
        snapshot = HealthSnapshot()
        error = nil
    }
    func preview() {
        clearReadings()
        isDemo = true
        snapshot = DemoData.snapshot(now: now)
        tab = .overview
    }
    func endPreview() {
        clearReadings()
        isDemo = false
        refresh()
    }
    func chooseConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose your Google Desktop OAuth client JSON. It will be stored in your Mac's Keychain."
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            do {
                clearReadings()
                isDemo = false
                try auth.importConfiguration(url)
                refresh()
            } catch { self.error = error.localizedDescription }
        }
    }
    func connect() {
        if !hasConfiguration { chooseConfiguration() }
        guard hasConfiguration else { return }
        if isDemo { endPreview() }
        auth.connect()
    }
    func disconnect() {
        do { try auth.disconnect(); clearReadings(); isDemo = false }
        catch { self.error = error.localizedDescription }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { self.error = "Couldn't update launch at login: \(error.localizedDescription)" }
    }
    func age(_ date: Date?) -> String {
        guard let date else { return "Not synced yet" }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
    var heartIsStale: Bool { snapshot.latestHeart.map { now.timeIntervalSince($0.time) > 900 } ?? true }
    var menuTitle: String {
        guard isConnected || isDemo else { return "Air" }
        var parts: [String] = []
        if showHeart { parts.append("♥ \(snapshot.latestHeart.map { "\(Int($0.bpm))\(heartIsStale ? "·" : "")" } ?? "—")") }
        if showSleep {
            let sleep = snapshot.latestSleep
            let value = HealthDate.duration(sleep?.minutesAsleep)
            let old = sleep.map { $0.day != HealthDate.day(now) } ?? false
            parts.append("☾ \(value)\(old ? "·" : "")")
        }
        if showSteps { parts.append("↗ \(snapshot.steps.map { Int($0).formatted() } ?? "—")") }
        if showHRV {
            let hrv = HealthSnapshot.latest(snapshot.hrv)
            parts.append("HRV \(hrv.map { "\(Int($0.value))\($0.day != HealthDate.day(now) ? "·" : "")" } ?? "—")")
        }
        return (isDemo ? "DEMO  " : "") + (parts.isEmpty ? "Air" : parts.joined(separator: "   "))
    }
}
