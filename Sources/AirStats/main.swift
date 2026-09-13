import AppKit
import Combine
import HealthCore
import SwiftUI

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
        store = AppStore(preview: isSnapshot)
        if let path = argument("--credentials") {
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
        if arguments.contains("--demo") || isSnapshot { store.preview() }
        if let tab = argument("--tab"), let selected = DashboardTab.allCases.first(where: { $0.rawValue.lowercased() == tab }) { store.tab = selected }
        if arguments.contains("--welcome") { store.endPreview() }
        let view = DashboardView(store: store)
        if let path = argument("--snapshot") {
            renderSnapshot(view, path: path)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.contentSize = NSSize(width: 404, height: 700)
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: view)
        subscription = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatus() }
        }
        updateStatus()
        store.refresh()
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
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Air Stats", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }
    @objc private func openFromMenu() { showPopover() }
    @objc private func refreshFromMenu() { store.refresh() }
    private func showPopover() {
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        if let checked = store.snapshot.fetchedAt, Date().timeIntervalSince(checked) > store.refreshInterval { store.refresh() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPopover(); return false }
    private func renderSnapshot(_ view: DashboardView, path: String) {
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 404, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.appearance = NSAppearance(named: argument("--appearance") == "light" ? .aqua : .darkAqua)
        window.setContentSize(NSSize(width: 404, height: 700))
        previewWindow = window
        window.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
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
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
