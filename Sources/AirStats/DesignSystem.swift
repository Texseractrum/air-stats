import AppKit
import SwiftUI

enum DashboardMetrics {
    static let width: CGFloat = 420
    static let height: CGFloat = 700
    static let inset: CGFloat = 20
    static let gap: CGFloat = 12
    static let radius: CGFloat = 20
}

enum Palette {
    static func stage(_ kind: String) -> Color {
        switch kind {
        case "DEEP": return .indigo
        case "REM": return .cyan
        case "AWAKE", "RESTLESS": return .orange
        default: return .blue
        }
    }
}

enum AirGlass {
    static var isAvailable: Bool {
        #if compiler(>=6.2) && !AIRSTATS_LEGACY_GLASS
        if #available(macOS 26.0, *), !ProcessInfo.processInfo.arguments.contains("--legacy-glass") { return true }
        #endif
        return false
    }
}

/// System preferences stay live. Preview-only overrides never change macOS settings.
@propertyWrapper
struct AccessibilityPreferences: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var systemContrast
    struct Values {
        var reduceMotion: Bool
        var reduceTransparency: Bool
        var increasedContrast: Bool
    }
    var wrappedValue: Values {
        let arguments = ProcessInfo.processInfo.arguments
        let preview = arguments.contains("--snapshot") || arguments.contains("--demo") || arguments.contains("--ui-smoke")
        return Values(reduceMotion: systemReduceMotion || (preview && arguments.contains("--reduce-motion")),
                      reduceTransparency: systemReduceTransparency || (preview && arguments.contains("--reduce-transparency")),
                      increasedContrast: systemContrast == .increased || (preview && arguments.contains("--high-contrast")))
    }
}

/// The glass layer is reserved for controls, not layered onto every metric card.
struct GlassControls<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        #if compiler(>=6.2) && !AIRSTATS_LEGACY_GLASS
        if #available(macOS 26.0, *), AirGlass.isAvailable {
            GlassEffectContainer(spacing: 8) { content }
        } else { content }
        #else
        content
        #endif
    }
}

struct ToolbarButtonStyle: ViewModifier {
    @AccessibilityPreferences private var accessibility
    func body(content: Content) -> some View {
        #if compiler(>=6.2) && !AIRSTATS_LEGACY_GLASS
        if #available(macOS 26.0, *), AirGlass.isAvailable, !accessibility.reduceTransparency {
            content.buttonStyle(.glass).buttonBorderShape(.circle)
        } else { content.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 10)) }
        #else
        content.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 10))
        #endif
    }
}

struct PrimaryButtonStyle: ViewModifier {
    @AccessibilityPreferences private var accessibility
    func body(content: Content) -> some View {
        #if compiler(>=6.2) && !AIRSTATS_LEGACY_GLASS
        if #available(macOS 26.0, *), AirGlass.isAvailable, !accessibility.reduceTransparency {
            content.buttonStyle(.glassProminent)
        } else { content.buttonStyle(.borderedProminent) }
        #else
        content.buttonStyle(.borderedProminent)
        #endif
    }
}

/// Let NSPopover supply its native material and window corners on macOS 26.
struct PopoverBackground: View {
    @AccessibilityPreferences private var accessibility
    var body: some View {
        if accessibility.reduceTransparency { Color(nsColor: .windowBackgroundColor) }
        else if AirGlass.isAvailable { Color.clear }
        else { Rectangle().fill(.regularMaterial) }
    }
}

struct Surface<Content: View>: View {
    var inset: CGFloat = 16
    @Environment(\.colorScheme) private var scheme
    @AccessibilityPreferences private var accessibility
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(inset).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: DashboardMetrics.radius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(accessibility.reduceTransparency ? 1 : scheme == .dark ? 0.65 : 0.88))
            }
            .overlay {
                RoundedRectangle(cornerRadius: DashboardMetrics.radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(accessibility.increasedContrast ? 0.35 : 0.055), lineWidth: accessibility.increasedContrast ? 1 : 0.5)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.04 : 0.025), radius: 8, y: 3)
    }
}

struct SectionLabel: View {
    var title: String
    var symbol: String
    var color: Color
    var body: some View {
        Label {
            Text(title).foregroundStyle(.primary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 16)
        }
        .font(.system(size: 12, weight: .semibold))
        .labelStyle(.titleAndIcon).fixedSize(horizontal: false, vertical: true)
    }
}

struct MetricValue: View {
    var value: String
    var unit: String = ""
    var compact = false
    var animateChanges = true
    @AccessibilityPreferences private var accessibility
    private var usesMotion: Bool { animateChanges && !accessibility.reduceMotion }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: compact ? 28 : 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(usesMotion ? .numericText() : .identity)
                .animation(usesMotion ? .smooth(duration: 0.3) : nil, value: value)
            if !unit.isEmpty { Text(unit).font(.system(size: 12)).foregroundStyle(.secondary) }
        }
        .lineLimit(1).minimumScaleFactor(0.75).accessibilityElement(children: .combine)
    }
}

struct ScoreRing: View {
    var value: Double?
    var color: Color
    @AccessibilityPreferences private var accessibility
    private var reduceMotion: Bool { accessibility.reduceMotion }
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.12), lineWidth: 5)
            Circle().trim(from: 0, to: min(1, max(0, (value ?? 0) / 100)))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: value)
            Text(value.map { "\(Int($0))%" } ?? "—")
                .font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: value)
        }.frame(width: 62, height: 62).padding(3)
            .accessibilityElement(children: .ignore).accessibilityLabel("Sleep efficiency")
            .accessibilityValue(value.map { "\(Int($0)) percent" } ?? "Unavailable")
    }
}

struct EmptyMetric: View {
    var message: String
    init(_ message: String) { self.message = message }
    var body: some View {
        Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
    }
}

enum DisplayDate {
    /// Parse a civil day locally; converting through UTC can move the date.
    static func label(_ day: String?) -> String {
        guard let day else { return "No measurement yet" }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) else { return day }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
