import AppKit
import Charts
import HealthCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: AppStore
    var dismiss: () -> Void = {}
    @AccessibilityPreferences private var accessibility
    @State private var lastMetricTab: DashboardTab = .overview
    private static let appIcon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
    private var pageAnimation: Animation? { accessibility.reduceMotion ? nil : .easeOut(duration: 0.15) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.isDemo { demoBanner }
            if store.tab == .settings {
                SettingsView(store: store).transition(.opacity)
            } else if store.isConnected || store.isDemo {
                navigation
                if store.tab == .overview {
                    VStack(alignment: .leading, spacing: 10) {
                        pageTitle
                        overview
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DashboardMetrics.inset).padding(.bottom, 12)
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: DashboardMetrics.gap) {
                                if let error = store.error ?? store.auth.error { errorNotice(error) }
                                pageTitle
                                Group {
                                    switch store.tab {
                                    case .sleep: sleepDetail
                                    case .vitals: vitals
                                    case .overview, .settings: EmptyView()
                                    }
                                }.id(store.tab).transition(.opacity)
                            }.padding(.horizontal, DashboardMetrics.inset).padding(.bottom, 20).id("top")
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .onChange(of: store.tab) { _, _ in proxy.scrollTo("top", anchor: .top) }
                    }
                }
            } else {
                ScrollView {
                    if let error = store.error ?? store.auth.error { errorNotice(error).padding(.horizontal, DashboardMetrics.inset) }
                    welcome
                }.scrollBounceBehavior(.basedOnSize)
            }
            footer
        }
        // Keep one edge-to-edge popover, including when macOS always shows scrollbars.
        // Unlike .hidden, .never also removes the mouse/legacy-scroller gutter.
        .scrollIndicators(.never)
        .frame(width: DashboardMetrics.width, height: DashboardMetrics.height)
        .background { PopoverBackground() }
        .animation(pageAnimation, value: store.tab)
        .animation(pageAnimation, value: store.isDemo)
        .onChange(of: store.tab) { _, tab in if tab != .settings { lastMetricTab = tab } }
        .onExitCommand {
            if store.tab == .settings { store.tab = lastMetricTab }
            else { dismiss() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = Self.appIcon { Image(nsImage: icon).resizable().interpolation(.high) }
                else { Image(systemName: "heart.fill").resizable().scaledToFit().foregroundStyle(.tint).padding(7) }
            }.frame(width: 36, height: 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.tab == .settings ? "Settings" : "Air Stats").font(.system(size: 17, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(store.tab == .settings ? "Air Stats" : "Your daily health, at a glance")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            GlassControls {
                HStack(spacing: 8) {
                    Button { store.refresh() } label: {
                        ZStack {
                            Image(systemName: "arrow.clockwise").opacity(store.isRefreshing ? 0 : 1)
                            if store.isRefreshing { ProgressView().controlSize(.small) }
                        }.frame(width: 20, height: 24)
                    }
                    .accessibilityLabel(store.isRefreshing ? "Refreshing" : "Refresh now")
                    .modifier(ToolbarButtonStyle())
                    .disabled(!store.isConnected || store.isRefreshing || store.isDemo)
                    .help("Refresh now (⌘R)")
                    .keyboardShortcut("r", modifiers: .command)
                    Button { store.tab = store.tab == .settings ? lastMetricTab : .settings } label: {
                        Image(systemName: store.tab == .settings ? "xmark" : "gearshape").frame(width: 20, height: 24)
                    }
                    .accessibilityLabel(store.tab == .settings ? "Done" : "Settings")
                    .accessibilityIdentifier("settings-button")
                    .modifier(ToolbarButtonStyle())
                    .help(store.tab == .settings ? "Done (Escape)" : "Settings (⌘,)")
                    .keyboardShortcut(",", modifiers: .command)
                }.font(.system(size: 13, weight: .medium))
            }
        }.padding(.horizontal, DashboardMetrics.inset).padding(.top, 16).padding(.bottom, 14)
    }

    private var navigation: some View {
        Picker("Health category", selection: $store.tab) {
            Text("Overview").tag(DashboardTab.overview)
            Text("Sleep").tag(DashboardTab.sleep)
            Text("Vitals").tag(DashboardTab.vitals)
        }.pickerStyle(.segmented).labelsHidden().controlSize(.large)
            .accessibilityIdentifier("health-category")
            .padding(.horizontal, DashboardMetrics.inset).padding(.bottom, 8)
    }

    private var demoBanner: some View {
        HStack {
            Label("Preview · sample data", systemImage: "sparkles").foregroundStyle(.secondary)
            Spacer()
            Button("Exit preview") { store.endPreview() }.buttonStyle(.borderless)
        }.font(.system(size: 11)).padding(.horizontal, DashboardMetrics.inset).padding(.bottom, 12)
    }

    private var pageTitle: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(store.tab == .overview ? "Today" : store.tab.rawValue)
                .font(.system(size: 22, weight: .bold)).accessibilityAddTraits(.isHeader)
            Spacer()
            Text(store.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }.padding(.bottom, 2)
    }

    private func errorNotice(_ error: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(title: "Connection needs attention", symbol: "exclamationmark.triangle", color: .orange)
                    Spacer()
                    Button { store.error = nil; store.auth.error = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).accessibilityLabel("Dismiss error")
                }
                Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if store.tab != .settings { Button("Open connection settings") { store.tab = .settings }.controlSize(.small) }
            }
        }
    }

    private var overview: some View {
        Group {
            sleepSummary
            heartCard
            Grid(horizontalSpacing: DashboardMetrics.gap, verticalSpacing: DashboardMetrics.gap) {
                GridRow {
                    compactMetric("Steps", icon: "figure.walk", value: store.snapshot.steps.map { Int($0).formatted() } ?? "—", unit: "steps", color: .orange, caption: "Today")
                    compactMetric("Heart rate variability", icon: "waveform.path", value: number(HealthSnapshot.latest(store.snapshot.hrv)?.value), unit: "ms", color: .teal, caption: DisplayDate.label(HealthSnapshot.latest(store.snapshot.hrv)?.day))
                }
            }
            if store.error != nil || store.auth.error != nil || !store.snapshot.issues.isEmpty {
                Button { store.tab = .settings } label: {
                    Label("Connection needs attention · Open Settings", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.borderless).accessibilityIdentifier("overview-connection-details")
                    .frame(height: 28)
            } else {
                Label("Sleep Score & Readiness are only available in Fitbit.", systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).frame(height: 28, alignment: .leading)
                    .accessibilityIdentifier("overview-score-note")
            }
        }
    }

    private var sleepSummary: some View {
        Surface(inset: store.tab == .overview ? 12 : 16) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(title: "Latest sleep", symbol: "moon.fill", color: .purple)
                    MetricValue(value: HealthDate.duration(store.snapshot.latestSleep?.minutesAsleep))
                    Text(store.snapshot.latestSleep.map { "Night ending \(DisplayDate.label($0.day))" } ?? "Appears after your next sync")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    ScoreRing(value: store.snapshot.latestSleep?.efficiency, color: .purple)
                    Text("Efficiency").font(.system(size: 11)).foregroundStyle(.secondary)
                }.help("Time asleep ÷ time in bed. This is not Fitbit's Sleep Score.")
            }
        }
    }

    private var heartCard: some View {
        HeartCard(samples: store.snapshot.heart, latest: store.snapshot.latestHeart,
                  latestAge: store.age(store.snapshot.latestHeart?.time), latestIsStale: store.heartIsStale,
                  compact: store.tab == .overview)
    }

    private func compactMetric(_ title: String, icon: String, value: String, unit: String, color: Color, caption: String) -> some View {
        Surface(inset: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: title, symbol: icon, color: color).frame(minHeight: 20, alignment: .topLeading)
                MetricValue(value: value, unit: unit, compact: true)
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var scoreAvailability: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sleep Score & Readiness").fontWeight(.medium)
                Text("Available in the Fitbit app, but not shared through Google's API.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } icon: { Image(systemName: "info.circle").foregroundStyle(.secondary) }
        .font(.system(size: 12)).padding(.horizontal, 2).padding(.vertical, 4)
    }

    private var sleepDetail: some View {
        Group {
            sleepSummary
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Last 7 nights", symbol: "chart.bar", color: .purple)
                    if mainNights.isEmpty { EmptyMetric("Sleep history appears after your tracker syncs.") }
                    else {
                        SleepHistoryChart(nights: mainNights).frame(height: 138)
                    }
                }
            }
            if let sleep = store.snapshot.latestSleep {
                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(title: "Sleep stages", symbol: "moon.zzz", color: .purple)
                        if !sleep.processed { EmptyMetric("Google is still processing this sleep session.") }
                        if !sleep.stages.isEmpty {
                            SleepStagesChart(stages: sleep.stages).frame(height: 134)
                        }
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            ForEach(["DEEP", "LIGHT", "REM", "AWAKE", "ASLEEP", "RESTLESS"], id: \.self) { kind in
                                if let minutes = sleep.stageMinutes[kind] {
                                    GridRow {
                                        HStack(spacing: 8) {
                                            Circle().fill(Palette.stage(kind)).frame(width: 6, height: 6)
                                            Text(kind == "REM" ? kind : kind.capitalized).foregroundStyle(.secondary)
                                        }
                                        Text(HealthDate.duration(minutes)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                }
                            }
                        }.font(.system(size: 12))
                        if sleep.stageMinutes.isEmpty && sleep.stages.isEmpty { EmptyMetric("No stage breakdown was supplied for this session.") }
                    }
                }
            }
            scoreAvailability
        }
    }

    private var mainNights: [SleepSession] {
        Array(store.snapshot.representativeSleepByDay.suffix(7))
    }

    private var vitals: some View {
        Group {
            heartCard
            Grid(horizontalSpacing: DashboardMetrics.gap, verticalSpacing: DashboardMetrics.gap) {
                GridRow {
                    dailyCard("Resting heart rate", symbol: "heart", values: store.snapshot.restingHeart, unit: "bpm", color: .pink)
                    dailyCard("Heart rate variability", symbol: "waveform.path", values: store.snapshot.hrv, unit: "ms", color: .teal)
                }
                GridRow {
                    dailyCard("Blood oxygen", symbol: "drop", values: store.snapshot.oxygen, unit: "%", color: .blue, digits: 1)
                    dailyCard("Breathing rate", symbol: "lungs", values: store.snapshot.respiration, unit: "/min", color: .purple, digits: 1)
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "Skin temperature", symbol: "thermometer.medium", color: .orange)
                    HStack(alignment: .firstTextBaseline) {
                        MetricValue(value: HealthSnapshot.latest(store.snapshot.temperature).map { String(format: "%+.1f", $0.value) } ?? "—", unit: "°C", compact: true)
                        Spacer()
                        Text(DisplayDate.label(HealthSnapshot.latest(store.snapshot.temperature)?.day)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text("Change from your 30-day baseline").font(.system(size: 12)).foregroundStyle(.secondary)
                    DailyMetricChart(title: "Skin temperature", values: store.snapshot.temperature, unit: "°C", color: .orange, digits: 1)
                        .frame(height: 100)
                }
            }
            Text("Heart rate updates after your tracker syncs to your phone, not as a live Bluetooth stream. Overnight metrics depend on your device and recorded data.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dailyCard(_ title: String, symbol: String, values: [DailyMetric], unit: String, color: Color, digits: Int = 0) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: title, symbol: symbol, color: color).frame(minHeight: 30, alignment: .topLeading)
                MetricValue(value: number(HealthSnapshot.latest(values)?.value, digits: digits), unit: unit, compact: true)
                if !values.isEmpty {
                    DailyMetricChart(title: title, values: values, unit: unit, color: color, digits: digits)
                        .frame(height: 100)
                } else {
                    Color.clear.frame(height: 100).accessibilityHidden(true)
                    Text("No measurement yet").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Image(systemName: "heart.text.clipboard").font(.system(size: 52, weight: .light)).foregroundStyle(.tint)
                .frame(height: 96).accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Your rhythm.\nOne glance away.").font(.system(size: 28, weight: .semibold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Text("Sleep, heart rate, and daily movement.\nA quiet home for your Fitbit in the menu bar.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(3)
            }.multilineTextAlignment(.center)
            VStack(spacing: 12) {
                Button { store.connect() } label: {
                    HStack(spacing: 8) {
                        if store.auth.isSigningIn { ProgressView().controlSize(.small) }
                        else { Image(systemName: "person.crop.circle") }
                        Text(store.auth.isSigningIn ? "Waiting for Google…" : "Connect with Google")
                    }.foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 4)
                }.modifier(PrimaryButtonStyle()).controlSize(.large).disabled(store.auth.isSigningIn)
                if store.auth.isSigningIn { Button("Cancel sign-in") { store.auth.cancelSignIn() }.buttonStyle(.borderless) }
                else { Button("Preview sample data") { store.preview() }.buttonStyle(.borderless) }
            }.font(.system(size: 13))
            Label("Read-only access. Credentials stay in Keychain.", systemImage: "lock.shield")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(.horizontal, 36).padding(.vertical, 42).frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let device = store.snapshot.devices.first {
                Image(systemName: "applewatch.side.right").foregroundStyle(.secondary).accessibilityHidden(true)
                Text(device.name).lineLimit(1).help(device.name)
                if let battery = device.battery {
                    Text("\(Int(battery))%").foregroundStyle(.secondary).accessibilityLabel("Battery \(Int(battery)) percent")
                }
                Spacer(minLength: 8)
                Text("Synced \(store.age(device.lastSync).lowercased())").foregroundStyle(.secondary).lineLimit(1)
                    .help(device.lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "Not synced yet")
            } else {
                Label(store.isConnected ? "Checked \(store.age(store.snapshot.fetchedAt).lowercased())" : "Private by design", systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }.font(.system(size: 11)).padding(.horizontal, DashboardMetrics.inset).padding(.vertical, 13)
            .overlay(alignment: .top) { Divider().padding(.horizontal, DashboardMetrics.inset) }
    }
    private func number(_ value: Double?, digits: Int = 0) -> String { value.map { String(format: "%.*f", digits, $0) } ?? "—" }
}

private struct HeartCard: View {
    var samples: [HeartSample]
    var latest: HeartSample?
    var latestAge: String
    var latestIsStale: Bool
    var compact: Bool
    @State private var selectedTime: Date?
    private let buckets: [TrendPoint]
    private let linePoints: [TrendPoint]
    private let isolatedPoints: [TrendPoint]
    private let pointsByTime: [Date: TrendPoint]

    init(samples: [HeartSample], latest: HeartSample?, latestAge: String, latestIsStale: Bool, compact: Bool) {
        self.samples = samples
        self.latest = latest
        self.latestAge = latestAge
        self.latestIsStale = latestIsStale
        self.compact = compact
        let buckets = ChartSeries.heart(samples)
        self.buckets = buckets
        let isolated = ChartSeries.isolatedSeries(buckets)
        linePoints = buckets.filter { !isolated.contains($0.series) }
        isolatedPoints = buckets.filter { isolated.contains($0.series) }
        pointsByTime = Dictionary(uniqueKeysWithValues: buckets.map { ($0.time, $0) })
    }
    private var selected: TrendPoint? {
        point(nearest: selectedTime)
    }
    private var displayedValue: Double? { selected?.value ?? latest?.bpm }
    private var displayedTime: String {
        selected?.time.formatted(.dateTime.month(.abbreviated).day().hour().minute()) ?? latestAge
    }
    private var timeDomain: ClosedRange<Date> {
        let first = buckets.first?.time ?? Date()
        return first.addingTimeInterval(-150)...(buckets.last?.time ?? first).addingTimeInterval(150)
    }
    private var valueDomain: ClosedRange<Double> {
        ChartSeries.domain(buckets.map(\.value), minimumSpan: 30, floor: 0)
    }
    private var detail: String {
        if let selected {
            return "\(selected.time.formatted(.dateTime.month(.abbreviated).day().hour().minute())) · \(Int(selected.value.rounded())) bpm average"
        }
        if let selectedTime { return "\(selectedTime.formatted(.dateTime.hour().minute())) · No reading" }
        if buckets.count == 1, let point = buckets.first { return "One recorded interval · \(Int(point.value.rounded())) bpm average" }
        let readings = samples.map(\.bpm).filter { $0.isFinite && $0 > 0 }
        guard let low = readings.min(), let high = readings.max() else { return "No readings yet" }
        return "Range \(Int(low.rounded()))–\(Int(high.rounded())) bpm · 5-min averages"
    }
    private var plot: some View {
        HeartPlotCanvas(linePoints: linePoints, isolatedPoints: isolatedPoints, selected: selected,
                        timeDomain: timeDomain, valueDomain: valueDomain, selection: updateSelection)
            .modifier(ChartKeyboardFocus())
            .onMoveCommand(perform: moveSelection)
            .accessibilityLabel("Heart rate. \(detail). Time on the horizontal axis, beats per minute on the vertical axis. Gaps mean no readings.")
            .accessibilityValue(detail)
            .accessibilityIdentifier("heart-trend")
            .accessibilityAdjustableAction { moveAccessibleSelection($0) }
            .help("Recorded readings from the last 24 hours. The time axis spans available readings; gaps are not connected. Hover or use Left and Right Arrow for five-minute averages.")
    }
    var body: some View {
        Surface(inset: compact ? 12 : 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(title: "Heart rate", symbol: "heart.fill", color: .pink)
                    Spacer()
                    Label(selected == nil ? (latest == nil ? "Awaiting sync" : latestIsStale ? "Older reading" : "Latest synced") : "5-min average",
                          systemImage: selected == nil ? (latestIsStale ? "clock" : "checkmark.circle") : "clock")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline) {
                    MetricValue(value: number(displayedValue), unit: "bpm", animateChanges: selected == nil)
                        .accessibilityLabel("Heart rate")
                        .accessibilityValue("\(number(displayedValue)) beats per minute")
                        .accessibilityIdentifier("heart-rate-value")
                    Spacer()
                    Text(displayedTime).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Group {
                    if buckets.isEmpty { EmptyMetric("Sync your tracker to see heart-rate readings.") }
                    else {
                        VStack(alignment: .leading, spacing: 4) {
                            plot
                            Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                        }
                    }
                }.frame(height: compact ? 104 : 144)
            }
        }.onDisappear { updateSelection(nil) }
    }

    private func point(nearest time: Date?) -> TrendPoint? {
        guard let time else { return nil }
        let bucket = Date(timeIntervalSince1970: (time.timeIntervalSince1970 / 300).rounded() * 300)
        return pointsByTime[bucket]
    }

    private func updateSelection(_ time: Date?) {
        let point = point(nearest: time)
        let bucketTime = time.map { Date(timeIntervalSince1970: ($0.timeIntervalSince1970 / 300).rounded() * 300) }
        let resolvedTime = point?.time ?? bucketTime
        guard selectedTime != resolvedTime else { return }
        selectedTime = resolvedTime
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !buckets.isEmpty, direction == .left || direction == .right else { return }
        let current = selected.flatMap { item in buckets.firstIndex(where: { $0.id == item.id }) }
        let index: Int
        if let current {
            index = min(buckets.count - 1, max(0, current + (direction == .right ? 1 : -1)))
        } else {
            index = direction == .right ? 0 : buckets.count - 1
        }
        updateSelection(buckets[index].time)
    }

    private func moveAccessibleSelection(_ direction: AccessibilityAdjustmentDirection) {
        if direction == .increment { moveSelection(.right) }
        else if direction == .decrement { moveSelection(.left) }
    }

    private func number(_ value: Double?) -> String { value.map { String(format: "%.0f", $0) } ?? "—" }
}

private struct HeartPlotCanvas: View {
    var linePoints: [TrendPoint]
    var isolatedPoints: [TrendPoint]
    var selected: TrendPoint?
    var timeDomain: ClosedRange<Date>
    var valueDomain: ClosedRange<Double>
    var selection: (Date?) -> Void

    private func plotFrame(_ size: CGSize) -> CGRect {
        CGRect(x: 31, y: 3, width: max(1, size.width - 35), height: max(1, size.height - 21))
    }
    private func x(_ time: Date, in frame: CGRect) -> CGFloat {
        let duration = max(0.001, timeDomain.upperBound.timeIntervalSince(timeDomain.lowerBound))
        return frame.minX + frame.width * time.timeIntervalSince(timeDomain.lowerBound) / duration
    }
    private func y(_ value: Double, in frame: CGRect) -> CGFloat {
        let span = max(0.001, valueDomain.upperBound - valueDomain.lowerBound)
        return frame.maxY - frame.height * (value - valueDomain.lowerBound) / span
    }

    var body: some View {
        Canvas { context, size in
            let frame = plotFrame(size)
            let yValues = [valueDomain.lowerBound, (valueDomain.lowerBound + valueDomain.upperBound) / 2, valueDomain.upperBound]
            for value in yValues {
                let position = y(value, in: frame)
                var grid = Path()
                grid.move(to: CGPoint(x: frame.minX, y: position))
                grid.addLine(to: CGPoint(x: frame.maxX, y: position))
                context.stroke(grid, with: .color(Color.secondary.opacity(0.25)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                context.draw(Text("\(Int(value.rounded()))").font(.system(size: 10)).foregroundStyle(.secondary),
                             at: CGPoint(x: frame.minX - 5, y: position), anchor: .trailing)
            }

            let midpoint = timeDomain.lowerBound.addingTimeInterval(timeDomain.upperBound.timeIntervalSince(timeDomain.lowerBound) / 2)
            let xValues = [timeDomain.lowerBound, midpoint, timeDomain.upperBound]
            let xAnchors: [UnitPoint] = [.topLeading, .top, .topTrailing]
            let sameDay = Calendar.current.isDate(timeDomain.lowerBound, inSameDayAs: timeDomain.upperBound)
            for (index, value) in xValues.enumerated() {
                let label = value.formatted(sameDay ? .dateTime.hour().minute() : .dateTime.day().hour())
                context.draw(Text(label).font(.system(size: 10)).foregroundStyle(.secondary),
                             at: CGPoint(x: x(value, in: frame), y: frame.maxY + 4), anchor: xAnchors[index])
            }

            var clipped = context
            clipped.clip(to: Path(frame))
            var line = Path()
            var previousSeries: Int?
            for point in linePoints {
                let position = CGPoint(x: x(point.time, in: frame), y: y(point.value, in: frame))
                if previousSeries == point.series { line.addLine(to: position) }
                else { line.move(to: position); previousSeries = point.series }
            }
            clipped.stroke(line, with: .color(.pink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            for point in isolatedPoints {
                let rect = CGRect(x: x(point.time, in: frame) - 5, y: y(point.value, in: frame) - 1.5, width: 10, height: 3)
                clipped.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(.pink))
            }
            if let selected {
                var rule = Path()
                let position = x(selected.time, in: frame)
                rule.move(to: CGPoint(x: position, y: frame.minY))
                rule.addLine(to: CGPoint(x: position, y: frame.maxY))
                clipped.stroke(rule, with: .color(Color.secondary.opacity(0.42)), lineWidth: 1)
            }
        }
        .overlay {
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let frame = plotFrame(geometry.size)
                            guard frame.contains(location) else { selection(nil); return }
                            let fraction = (location.x - frame.minX) / frame.width
                            let interval = timeDomain.upperBound.timeIntervalSince(timeDomain.lowerBound) * fraction
                            selection(timeDomain.lowerBound.addingTimeInterval(interval))
                        case .ended:
                            selection(nil)
                        }
                    }
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct SleepHistoryChart: View {
    var nights: [SleepSession]
    @State private var selectedDay: String?
    private var selected: SleepSession? {
        guard let selectedDay else { return nil }
        return nights.first { $0.day == selectedDay }
    }
    private var detail: String {
        guard let selected else {
            let durations = nights.compactMap(\.minutesAsleep)
            guard !durations.isEmpty else { return "No recorded sleep duration" }
            return "Average \(HealthDate.duration(durations.reduce(0, +) / Double(durations.count))) · \(durations.count) recorded nights"
        }
        return "\(DisplayDate.label(selected.day)) · \(HealthDate.duration(selected.minutesAsleep))"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Chart {
                ForEach(nights) { night in
                    if let minutes = night.minutesAsleep, let date = ChartSeries.civilDate(night.day) {
                        BarMark(x: .value("Night ending", date, unit: .day), y: .value("Hours asleep", minutes / 60))
                            .foregroundStyle(Color.purple.opacity(selected == nil || selected?.id == night.id ? 0.9 : 0.35))
                            .cornerRadius(4)
                            .accessibilityLabel("\(DisplayDate.label(night.day)), \(HealthDate.duration(minutes))")
                    }
                }
                if let selected, let date = ChartSeries.civilDate(selected.day) {
                    RuleMark(x: .value("Selected night", date))
                        .foregroundStyle(Color.secondary.opacity(0.38))
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) { Text(date.formatted(.dateTime.day().month(.abbreviated))) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel { if let hours = value.as(Double.self) { Text("\(hours, specifier: "%.0f")h") } }
                }
            }
            .chartOverlay { proxy in
                ChartHoverOverlay(proxy: proxy, valueType: Date.self) { selectedDay = $0.map { HealthDate.day($0) } }
            }
            .modifier(ChartKeyboardFocus())
            .onMoveCommand(perform: moveSelection)
            .accessibilityLabel("Sleep duration for the last seven nights. \(detail)")
            .accessibilityValue(detail)
            .accessibilityAdjustableAction { moveAccessibleSelection($0) }
            .help("Move over the chart for exact values. Use Left and Right Arrow when focused.")
            Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !nights.isEmpty, direction == .left || direction == .right else { return }
        let current = selected.flatMap { item in nights.firstIndex(where: { $0.id == item.id }) }
        let index: Int
        if let current {
            index = min(nights.count - 1, max(0, current + (direction == .right ? 1 : -1)))
        } else {
            index = direction == .right ? 0 : nights.count - 1
        }
        selectedDay = nights[index].day
    }

    private func moveAccessibleSelection(_ direction: AccessibilityAdjustmentDirection) {
        if direction == .increment { moveSelection(.right) }
        else if direction == .decrement { moveSelection(.left) }
    }
}

private struct SleepStagesChart: View {
    var stages: [SleepStage]
    @State private var selectedTime: Date?
    private var selected: SleepStage? {
        guard let selectedTime else { return nil }
        return stages.first(where: { $0.start <= selectedTime && selectedTime < $0.end })
    }
    private var detail: String {
        guard let selectedTime else { return "Sleep stage timeline" }
        guard let selected else { return "\(selectedTime.formatted(.dateTime.hour().minute())) · No stage recorded" }
        let kind = selected.kind == "REM" ? "REM" : selected.kind.capitalized
        return "\(selectedTime.formatted(.dateTime.hour().minute())) · \(kind) · \(Int(selected.minutes.rounded())) min"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Chart {
                ForEach(stages) { stage in
                    RectangleMark(
                        xStart: .value("Start", stage.start),
                        xEnd: .value("End", stage.end),
                        y: .value("Stage", stage.kind == "REM" ? "REM" : stage.kind.capitalized)
                    )
                    .foregroundStyle(Palette.stage(stage.kind).opacity(selected == nil || selected?.id == stage.id ? 1 : 0.38))
                    .cornerRadius(3)
                    .accessibilityLabel("\(stage.kind), \(Int(stage.minutes.rounded())) minutes")
                }
                if let selectedTime {
                    RuleMark(x: .value("Selected time", selectedTime))
                        .foregroundStyle(Color.primary.opacity(0.48))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 3)) { _ in AxisValueLabel(format: .dateTime.hour().minute()) } }
            .chartYAxis { AxisMarks(position: .leading) }
            .chartOverlay { proxy in
                ChartHoverOverlay(proxy: proxy, valueType: Date.self) { selectedTime = $0 }
            }
            .modifier(ChartKeyboardFocus())
            .onMoveCommand(perform: moveSelection)
            .accessibilityLabel("Sleep stages over time. \(detail)")
            .accessibilityValue(detail)
            .accessibilityAdjustableAction { moveAccessibleSelection($0) }
            .help("Move over the chart for exact values. Use Left and Right Arrow when focused.")
            Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !stages.isEmpty, direction == .left || direction == .right else { return }
        let current = selected.flatMap { item in stages.firstIndex(where: { $0.id == item.id }) }
        let index: Int
        if let current {
            index = min(stages.count - 1, max(0, current + (direction == .right ? 1 : -1)))
        } else {
            index = direction == .right ? 0 : stages.count - 1
        }
        let stage = stages[index]
        selectedTime = stage.start.addingTimeInterval(stage.end.timeIntervalSince(stage.start) / 2)
    }

    private func moveAccessibleSelection(_ direction: AccessibilityAdjustmentDirection) {
        if direction == .increment { moveSelection(.right) }
        else if direction == .decrement { moveSelection(.left) }
    }
}

private struct DailyMetricChart: View {
    var title: String
    var values: [DailyMetric]
    var unit: String
    var color: Color
    var digits: Int
    @State private var selectedDay: String?
    private var points: [TrendPoint] { ChartSeries.daily(values) }
    private var isolated: Set<Int> { ChartSeries.isolatedSeries(points) }
    private var timeDomain: ClosedRange<Date> {
        let first = points.first?.time ?? Date()
        let last = points.last?.time ?? first
        return first.addingTimeInterval(-43200)...last.addingTimeInterval(43200)
    }
    private var valueDomain: ClosedRange<Double> {
        let minimumSpan = unit == "°C" ? 1.0 : unit == "%" ? 10 : unit == "/min" ? 4 : 20
        return ChartSeries.domain(points.map(\.value) + (unit == "°C" ? [0] : []), minimumSpan: minimumSpan,
                                  floor: unit == "°C" ? nil : 0, ceiling: unit == "%" ? 100 : nil)
    }
    private var selected: DailyMetric? {
        selectedDay.flatMap { day in values.first { $0.day == day } }
    }
    private var detail: String {
        if let selectedDay, selected == nil { return "\(DisplayDate.label(selectedDay)) · No reading" }
        let point = selected ?? HealthSnapshot.latest(values)
        guard let point else { return "No measurement yet" }
        if selected == nil { return "\(DisplayDate.label(point.day)) · \(points.count) recorded \(points.count == 1 ? "day" : "days")" }
        let value = String(format: "%.*f", digits, point.value)
        let separator = unit == "%" ? "" : " "
        return "\(DisplayDate.label(point.day)) · \(value)\(separator)\(unit)"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Chart {
                ForEach(points) { point in
                    if isolated.contains(point.series) {
                        RectangleMark(x: .value("Date", point.time), y: .value(unit, point.value), width: .fixed(10), height: .fixed(3))
                            .foregroundStyle(color).cornerRadius(1.5)
                    } else {
                        LineMark(x: .value("Date", point.time), y: .value(unit, point.value), series: .value("Consecutive days", point.series))
                            .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.linear)
                    }
                }
                if let selected, let date = ChartSeries.civilDate(selected.day) {
                    RuleMark(x: .value("Selected date", date))
                        .foregroundStyle(Color.secondary.opacity(0.38))
                }
                if unit == "°C" {
                    RuleMark(y: .value("Baseline", 0)).foregroundStyle(Color.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXScale(domain: timeDomain)
            .chartYScale(domain: valueDomain)
            .chartXAxis {
                AxisMarks(values: Array(Set([points.first?.time, points.last?.time].compactMap { $0 })).sorted()) { value in
                    AxisValueLabel(anchor: points.count == 1 ? .top : value.index == 0 ? .topLeading : .topTrailing) {
                        if let date = value.as(Date.self) { Text(date.formatted(.dateTime.day().month(.abbreviated))) }
                    }.font(.system(size: 10))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(Color.secondary.opacity(0.25))
                    AxisValueLabel().font(.system(size: 9))
                }
            }
            .chartOverlay { proxy in
                ChartHoverOverlay(proxy: proxy, valueType: Date.self) { selectedDay = $0.map { HealthDate.day($0) } }
            }
            .modifier(ChartKeyboardFocus())
            .onMoveCommand(perform: moveSelection)
            .accessibilityLabel("\(title). \(detail). Recorded daily measurements in \(unit). Missing days are not connected.")
            .accessibilityValue(detail)
            .accessibilityAdjustableAction { moveAccessibleSelection($0) }
            .help("Move over the chart for exact values. Use Left and Right Arrow when focused.")
            Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !points.isEmpty, direction == .left || direction == .right else { return }
        let current = selectedDay.flatMap { day in points.firstIndex(where: { HealthDate.day($0.time) == day }) }
        let index: Int
        if let current {
            index = min(points.count - 1, max(0, current + (direction == .right ? 1 : -1)))
        } else {
            index = direction == .right ? 0 : points.count - 1
        }
        selectedDay = HealthDate.day(points[index].time)
    }

    private func moveAccessibleSelection(_ direction: AccessibilityAdjustmentDirection) {
        if direction == .increment { moveSelection(.right) }
        else if direction == .decrement { moveSelection(.left) }
    }
}

private struct ChartHoverOverlay<Value: Plottable>: View {
    var proxy: ChartProxy
    var valueType: Value.Type
    var selection: (Value?) -> Void

    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard let plotFrame = proxy.plotFrame else { selection(nil); return }
                        let frame = geometry[plotFrame]
                        guard frame.contains(location) else { selection(nil); return }
                        selection(proxy.value(atX: location.x - frame.minX, as: valueType))
                    case .ended:
                        selection(nil)
                    }
                }
                .accessibilityHidden(true)
        }
    }
}

private struct ChartKeyboardFocus: ViewModifier {
    func body(content: Content) -> some View {
        content
            .focusable(interactions: .edit)
    }
}
