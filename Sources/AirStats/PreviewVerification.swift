import AppKit
import HealthCore
import ScreenCaptureKit
import SwiftUI

/// Exercises only an isolated sample-data store and this process's own window.
/// No Accessibility or Screen Recording permission, real account, or desktop capture.
@MainActor
enum PreviewVerification {
    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    @available(macOS 14.4, *)
    static func capture(window: NSWindow, path: String) async throws {
        if ProcessInfo.processInfo.arguments.contains("--scroll-bottom") {
            guard let scroll = elements(in: window).compactMap({ $0.object as? NSScrollView }).first,
                  let document = scroll.documentView else { throw Failure(message: "This preview has no scrollable content.") }
            let y = document.isFlipped ? max(document.bounds.minY, document.bounds.maxY - scroll.contentSize.height) : document.bounds.minY
            document.scroll(NSPoint(x: 0, y: y))
            try await settle()
        }
        let content = try await SCShareableContent.currentProcess
        guard let ownWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }) else {
            throw Failure(message: "The sample window is not available for capture.")
        }
        let filter = SCContentFilter(desktopIndependentWindow: ownWindow)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * window.backingScaleFactor)
        configuration.height = Int(window.frame.height * window.backingScaleFactor)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let captured = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let bitmap = NSBitmapImageRep(cgImage: captured)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure(message: "PNG encoding failed.") }
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// SwiftUI's virtual elements use the public informal accessibility protocol,
    /// while AppKit controls conform to NSAccessibilityProtocol explicitly.
    @MainActor
    struct Element {
        let object: NSObject
        func attribute(_ getter: String, legacy: String) -> Any? {
            let selector = NSSelectorFromString(getter)
            if object.responds(to: selector) { return object.perform(selector)?.takeUnretainedValue() }
            let legacySelector = NSSelectorFromString("accessibilityAttributeValue:")
            guard object.responds(to: legacySelector) else { return nil }
            return object.perform(legacySelector, with: legacy)?.takeUnretainedValue()
        }
        func accessibilityChildren() -> [Any] { attribute("accessibilityChildren", legacy: "AXChildren") as? [Any] ?? [] }
        func accessibilityIdentifier() -> String? { attribute("accessibilityIdentifier", legacy: "AXIdentifier") as? String }
        func accessibilityLabel() -> String? {
            if let label = (attribute("accessibilityLabel", legacy: "AXDescription") as? String)
                ?? (attribute("accessibilityTitle", legacy: "AXTitle") as? String) { return label }
            if let title = attribute("accessibilityTitleUIElement", legacy: "AXTitleUIElement") as? NSObject {
                return Element(object: title).attribute("accessibilityValue", legacy: "AXValue") as? String
            }
            return nil
        }
        func accessibilityRole() -> String? { attribute("accessibilityRole", legacy: "AXRole") as? String }
        func accessibilityValue() -> String? { attribute("accessibilityValue", legacy: "AXValue") as? String }
        func increment() -> Bool {
            let selector = NSSelectorFromString("accessibilityPerformIncrement")
            guard object.responds(to: selector) else { return false }
            typealias Increment = @convention(c) (AnyObject, Selector) -> Bool
            return unsafeBitCast(object.method(for: selector), to: Increment.self)(object, selector)
        }
        func accessibilityPerformPress() -> Bool {
            if let control = object as? NSControl {
                guard control.isEnabled else { return false }
                control.performClick(nil)
                return true
            }
            let selector = NSSelectorFromString("accessibilityPerformPress")
            if object.responds(to: selector) {
                typealias Press = @convention(c) (AnyObject, Selector) -> Bool
                let implementation = unsafeBitCast(object.method(for: selector), to: Press.self)
                if implementation(object, selector) { return true }
            }
            let legacySelector = NSSelectorFromString("accessibilityPerformAction:")
            guard object.responds(to: legacySelector) else { return false }
            object.perform(legacySelector, with: "AXPress")
            return true
        }
    }

    static func elements(in window: NSWindow) -> [Element] {
        var visited = Set<ObjectIdentifier>()
        func visit(_ item: Any, depth: Int) -> [Element] {
            guard depth < 30, visited.count < 3000, let object = item as? NSObject else { return [] }
            guard visited.insert(ObjectIdentifier(object)).inserted else { return [] }
            let accessible = Element(object: object)
            return [accessible] + accessible.accessibilityChildren().flatMap { visit($0, depth: depth + 1) }
        }
        return visit(window, depth: 0)
    }

    static func settle() async throws { try await Task.sleep(nanoseconds: 700_000_000) }

    // SwiftUI republishes bindings and accessibility asynchronously, and a cold
    // launch is slower than a warm one. Polling keeps every assertion strict while
    // removing the timing dependency a fixed sleep bakes in.
    static func waitUntil(_ requirement: String, _ condition: () -> Bool) async throws {
        for attempt in 0..<40 {
            if condition() { return }
            if attempt < 39 { try await Task.sleep(nanoseconds: 50_000_000) }
        }
        throw Failure(message: requirement)
    }

    static func waitForElement(in window: NSWindow, _ requirement: String,
                               matching predicate: (Element) -> Bool) async throws -> Element {
        for attempt in 0..<40 {
            if let found = elements(in: window).first(where: predicate) { return found }
            if attempt < 39 { try await Task.sleep(nanoseconds: 50_000_000) }
        }
        throw Failure(message: requirement)
    }

    static func verifyNoScrollbars(in window: NSWindow, page: String) async throws {
        var scrollViews: [NSScrollView] = []
        for attempt in 0..<40 {
            scrollViews = elements(in: window).compactMap { $0.object as? NSScrollView }
            if !scrollViews.isEmpty { break }
            if attempt < 39 { try await Task.sleep(nanoseconds: 50_000_000) }
        }
        guard !scrollViews.isEmpty else { throw Failure(message: "No native scroll container found for \(page).") }
        for scroll in scrollViews {
            guard !scroll.hasVerticalScroller, !scroll.hasHorizontalScroller else {
                throw Failure(message: "\(page) must not reserve space for scrollbars.")
            }
        }
        print("PASS: \(page) has no scrollbars or scrollbar gutters")
    }

    // SwiftUI tears down a previous page's scroll container asynchronously, so a
    // cold launch can still expose one moments after the overview appears.
    // Polling keeps the assertion strict: a real scroll container never goes away.
    static func verifyOverviewIsFixed(in window: NSWindow) async throws {
        func hasScrollView(_ view: NSView) -> Bool {
            view is NSScrollView || view.subviews.contains(where: hasScrollView)
        }
        for attempt in 0..<20 {
            if let content = window.contentView, !hasScrollView(content) {
                print("PASS: Overview is a fixed layout with no scrolling")
                return
            }
            if attempt < 19 { try await Task.sleep(nanoseconds: 100_000_000) }
        }
        throw Failure(message: "Overview must have no scroll container, not merely hidden scrollbars.")
    }

    static func press(in window: NSWindow, matching predicate: (Element) -> Bool) async throws {
        // SwiftUI replaces virtual elements asynchronously during transitions.
        for _ in 0..<20 {
            if let element = elements(in: window).first(where: predicate), element.accessibilityPerformPress() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw Failure(message: "A native control did not become accessible and pressable.")
    }

    static func run(store: AppStore, window: NSWindow) async throws {
        if ProcessInfo.processInfo.arguments.contains("--onboarding") {
            guard !store.isDemo, !store.isConnected, !store.hasConfiguration else {
                throw Failure(message: "Onboarding checks require an isolated disconnected store.")
            }
            let onboardingControls = ["onboarding-connect", "onboarding-preview", "onboarding-dismiss"]
            try await waitUntil("Every onboarding action must be exposed to accessibility.") {
                let identifiers = Set(elements(in: window).compactMap { $0.accessibilityIdentifier() })
                return onboardingControls.allSatisfy(identifiers.contains)
            }
            let identifiers = Set(elements(in: window).compactMap { $0.accessibilityIdentifier() })
            guard !identifiers.contains("settings-button") else {
                throw Failure(message: "The dimmed dashboard must be hidden from accessibility while onboarding is open.")
            }
            print("PASS: onboarding traps interaction above the dimmed dashboard")
            try await press(in: window) { $0.accessibilityIdentifier() == "onboarding-preview" }
            try await waitUntil("The onboarding preview action did not open sample data.") { store.isDemo }
            try await waitUntil("Onboarding did not dismiss after choosing sample data.") {
                !elements(in: window).contains { $0.accessibilityIdentifier() == "onboarding-preview" }
            }
            print("PASS: onboarding sample-data action dismisses the modal")
            print("Onboarding UI verification passed; no real credentials or health data accessed.")
            return
        }
        guard store.isDemo, !store.isConnected, !store.hasConfiguration else { throw Failure(message: "UI checks require an isolated preview store.") }
        if ProcessInfo.processInfo.arguments.contains("--ui-perf") {
            let pattern: [Double] = [61, 63, 62, 60, 62, 65, 63, 62, 64, 63, 61, 64, 68, 66, 65, 63, 64, 62, 61, 64]
            store.snapshot.heart = (0..<1440).map { index in
                HeartSample(time: store.now.addingTimeInterval(Double(index - 1440) * 60), bpm: pattern[index % pattern.count])
            }
        }
        try await settle()
        try await verifyOverviewIsFixed(in: window)
        if !ChartSeries.heart(store.snapshot.heart).isEmpty {
            let firstAverage = ChartSeries.heart(store.snapshot.heart).first!.value
            let chart = try await waitForElement(in: window, "Heart-rate trend must be accessible.") {
                $0.accessibilityIdentifier() == "heart-trend"
            }
            guard chart.increment() else { throw Failure(message: "Chart must support accessible value selection.") }
            try await waitUntil("Selecting a chart reading must announce its time and average.") {
                elements(in: window).first { $0.accessibilityIdentifier() == "heart-trend" }?
                    .accessibilityLabel()?.contains("bpm average") == true
            }
            try await waitUntil("Selecting a chart reading must update the large heart-rate value.") {
                elements(in: window).first { $0.accessibilityIdentifier() == "heart-rate-value" }?
                    .accessibilityValue()?.contains("\(Int(firstAverage.rounded())) beats per minute") == true
            }
            print("PASS: chart selection updates the large value and exposes its timestamp")
            if ProcessInfo.processInfo.arguments.contains("--ui-perf") {
                // A cold launch pays for first-render, glyph, and layer setup once.
                // Warm those up first so the measurement reflects steady-state updates.
                for _ in 0..<10 {
                    guard chart.increment() else { throw Failure(message: "Chart selection failed while warming up.") }
                    try await Task.sleep(nanoseconds: 16_000_000)
                }
                // Measured back-to-back, with no frame pacing to dilute the result:
                // this is the per-selection update cost a moving cursor pays. Swift
                // Charts rebuilt its plot layout on every change and blew this budget.
                let start = CFAbsoluteTimeGetCurrent()
                for _ in 0..<40 {
                    guard chart.increment() else { throw Failure(message: "Chart selection failed during performance measurement.") }
                    await Task.yield()
                }
                let perSelection = (CFAbsoluteTimeGetCurrent() - start) / 40
                guard perSelection < 0.004 else {
                    throw Failure(message: String(format: "Each chart selection took %.2fms; expected under 4.00ms.", perSelection * 1000))
                }
                print(String(format: "PASS: chart selection costs %.2fms, within the 60fps frame budget", perSelection * 1000))
            }
        }
        try await press(in: window) { $0.accessibilityIdentifier() == "settings-button" }
        try await waitUntil("Settings action did not navigate.") { store.tab == .settings }
        try await verifyNoScrollbars(in: window, page: "Settings")
        print("PASS: native settings button")
        let showHeart = store.showHeart
        defer { store.showHeart = showHeart }
        try await press(in: window) { $0.accessibilityLabel() == "Heart rate" && $0.accessibilityRole() == "AXCheckBox" }
        try await waitUntil("The menu-bar toggle did not update its binding.") { store.showHeart != showHeart }
        print("PASS: native menu-bar toggle")
        store.showHeart = showHeart
        try await press(in: window) { $0.accessibilityIdentifier() == "settings-button" }
        try await waitUntil("Done did not return to the prior tab.") { store.tab == .overview }
        try await verifyOverviewIsFixed(in: window)
        print("PASS: return from settings")
        try await press(in: window) { $0.accessibilityLabel() == "Sleep" && $0.accessibilityRole() == "AXRadioButton" }
        try await waitUntil("Sleep segment did not navigate.") { store.tab == .sleep }
        try await verifyNoScrollbars(in: window, page: "Sleep")
        print("PASS: native segmented picker")
        try await press(in: window) { $0.accessibilityIdentifier() == "settings-button" }
        try await settle()
        guard let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else {
            throw Failure(message: "Cannot create Escape event.")
        }
        window.sendEvent(key)
        try await waitUntil("Escape must restore the previously selected tab.") { store.tab == .sleep }
        print("PASS: Escape restores prior tab")
        print("UI verification passed; no real credentials or health data accessed.")
    }
}
