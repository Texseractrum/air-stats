import AppKit
import Combine
import HealthCore
import SwiftUI

final class PreviewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var store: AppStore!
    private var subscription: AnyCancellable?
    private var previewWindow: NSWindow?
    private let arguments = ProcessInfo.processInfo.arguments
    private func argument(_ name: String) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let isSnapshot = argument("--snapshot") != nil
        let isPreview = isSnapshot || arguments.contains("--demo") || arguments.contains("--ui-smoke")
        store = AppStore(preview: isPreview)
        if !isPreview, let path = argument("--credentials") {
            do { try store.auth.importConfiguration(URL(fileURLWithPath: path)) }
            catch { store.error = error.localizedDescription }
        }
        if arguments.contains("--check-connection") {
            Task {
                guard store.isConnected else {
                    print("Google sign-in is not complete. Open Air Stats and connect your account.")
                    exit(2)
                }
                do {
                    let token = try await store.auth.accessToken()
                    let snapshot = try await HealthClient().snapshot(token: token)
                    let report: [String: Any] = [
                        "connected": true, "heartSamples": snapshot.heart.count, "sleepSessions": snapshot.sleep.count,
                        "hrvDays": snapshot.hrv.count, "restingHeartRateDays": snapshot.restingHeart.count,
                        "hasSteps": snapshot.steps != nil, "devices": snapshot.devices.count,
                        "sourceErrors": snapshot.issues
                    ]
                    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    print(String(decoding: data, as: UTF8.self))
                    exit(snapshot.issues.isEmpty ? 0 : 1)
                } catch { print(error.localizedDescription); exit(1) }
            }
            return
        }
        if isPreview { store.preview() }
        if let tab = argument("--tab"), let selected = DashboardTab.allCases.first(where: { $0.rawValue.lowercased() == tab }) { store.tab = selected }
        if arguments.contains("--welcome") || arguments.contains("--onboarding") { store.endPreview() }
        if isPreview {
            switch argument("--state") {
            case "empty": store.snapshot = HealthSnapshot()
            case "stale": store.now = store.now.addingTimeInterval(7200)
            case "loading": store.isRefreshing = true
            case "sparse":
                store.snapshot.heart = store.snapshot.heart.enumerated().filter { $0.offset % 60 < 20 }.map(\.element)
                store.snapshot.hrv = store.snapshot.hrv.enumerated().filter { $0.offset != 3 }.map(\.element)
                store.snapshot.restingHeart = store.snapshot.restingHeart.enumerated().filter { $0.offset != 3 }.map(\.element)
            case "single":
                store.snapshot.heart = Array(store.snapshot.heart.suffix(1))
                store.snapshot.hrv = Array(store.snapshot.hrv.suffix(1))
                store.snapshot.restingHeart = Array(store.snapshot.restingHeart.suffix(1))
                store.snapshot.oxygen = Array(store.snapshot.oxygen.suffix(1))
                store.snapshot.respiration = Array(store.snapshot.respiration.suffix(1))
            case "error":
                store.error = "Couldn't refresh your data. Check your internet connection, then try again. Your last synced readings are still available."
                store.snapshot.issues = ["heart-rate": "Google couldn't return heart-rate data. Reconnect in Settings and allow read-only access to health metrics."]
            default: break
            }
        }
        let dashboard = DashboardView(store: store, dismiss: { [weak self] in self?.popover.performClose(nil) })
        let view = OnboardingContainer(store: store, content: dashboard)
        if arguments.contains("--ui-smoke") {
            renderSnapshot(view, path: argument("--snapshot") ?? "")
            return
        }
        if let path = argument("--snapshot") {
            if arguments.contains("--popover") { renderPopoverSnapshot(view, path: path) }
            else { renderSnapshot(view, path: path) }
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "AirStatsStatusItem"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.contentSize = NSSize(width: DashboardMetrics.width, height: DashboardMetrics.height)
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentViewController = NSHostingController(rootView: view)
        subscription = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatus() }
        }
        updateStatus()
        store.refresh()
        if !isPreview { store.updates.startAutomaticChecks() }
        if arguments.contains("--connect") { store.connect() }
        if !store.isConnected || arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.showPopover() }
        }
    }
    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        button.title = store.menuTitle
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        button.setAccessibilityLabel("Air Stats: \(store.menuTitle)")
        button.toolTip = "Air Stats · \(store.isDemo ? "Sample data" : "Latest synced Fitbit readings")\nHeart rate: \(store.age(store.snapshot.latestHeart?.time))\nA trailing dot indicates an older reading."
    }
    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Air Stats", action: #selector(openFromMenu), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r").target = self
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdatesFromMenu), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Air Stats", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }
    @objc private func openFromMenu() { showPopover() }
    @objc private func refreshFromMenu() { store.refresh() }
    @objc private func checkForUpdatesFromMenu() { store.updates.checkForUpdates() }
    private func showPopover() {
        guard let button = statusItem?.button else { return }
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        if let checked = store.snapshot.fetchedAt, Date().timeIntervalSince(checked) > store.refreshInterval { store.refreshIfDue() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPopover(); return false }
    private func renderPopoverSnapshot<V: View>(_ view: V, path: String) {
        guard #available(macOS 14.4, *) else {
            fputs("Popover capture requires macOS 14.4 or later. Use --snapshot without --popover.\n", stderr)
            exit(1)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Air Preview"
        popover.contentSize = NSSize(width: DashboardMetrics.width, height: DashboardMetrics.height)
        popover.contentViewController = NSHostingController(rootView: view)
        popover.appearance = NSAppearance(named: argument("--appearance") == "light" ? .aqua : .darkAqua)
        popover.behavior = .applicationDefined
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.showPopover()
            Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 800_000_000)
                    guard let window = self.popover.contentViewController?.view.window else {
                        throw PreviewVerification.Failure(message: "Sample popover did not open.")
                    }
                    try await PreviewVerification.capture(window: window, path: path)
                    print("Rendered native popover \(path)")
                    exit(0)
                } catch { fputs("Popover snapshot failed: \(error.localizedDescription)\n", stderr); exit(1) }
            }
        }
    }
    private func renderSnapshot<V: View>(_ view: V, path: String) {
        // Render only the sample dashboard, never the desktop or a connected account.
        let controller = NSHostingController(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        let window = PreviewWindow(contentRect: NSRect(x: 0, y: 0, width: DashboardMetrics.width, height: DashboardMetrics.height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.appearance = NSAppearance(named: argument("--appearance") == "light" ? .aqua : .darkAqua)
        window.setContentSize(NSSize(width: DashboardMetrics.width, height: DashboardMetrics.height))
        previewWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if arguments.contains("--ui-smoke") {
            Task { @MainActor in
                do { try await PreviewVerification.run(store: store, window: window); exit(0) }
                catch { fputs("UI verification failed: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if self.arguments.contains("--composited"), #available(macOS 14.4, *) {
                Task { @MainActor in
                    do { try await PreviewVerification.capture(window: window, path: path); print("Rendered composited \(path)"); exit(0) }
                    catch { fputs("Composited snapshot failed: \(error.localizedDescription)\n", stderr); exit(1) }
                }
                return
            }
            let content = controller.view
            content.layoutSubtreeIfNeeded()
            guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { exit(1) }
            content.cacheDisplay(in: content.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
            do { try data.write(to: URL(fileURLWithPath: path)); print("Rendered \(path)"); exit(0) }
            catch { fputs("Snapshot failed\n", stderr); exit(1) }
        }
    }
}

MainActor.assumeIsolated {
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--mcp") {
        AgentMCP.run()
    } else if arguments.contains("--install-agent-integration") {
        do {
            print(try AgentIntegration().install().message)
            exit(0)
        } catch {
            fputs("Agent integration failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    } else if arguments.contains("--remove-agent-integration") {
        do {
            print(try AgentIntegration().uninstall().message)
            exit(0)
        } catch {
            fputs("Agent integration removal failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    } else {
        let isPreview = arguments.contains("--snapshot") || arguments.contains("--demo") || arguments.contains("--ui-smoke")
        if !isPreview { Task.detached { AgentIntegration().refreshInstalledFilesIfEnabled() } }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
