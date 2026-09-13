import AppKit
import Charts
import HealthCore
import SwiftUI

enum Palette {
    static let green = Color(red: 0.35, green: 0.77, blue: 0.60)
    static let purple = Color(red: 0.65, green: 0.57, blue: 0.92)
    static let coral = Color(red: 0.93, green: 0.48, blue: 0.44)
    static let blue = Color(red: 0.40, green: 0.66, blue: 0.89)
    static let gold = Color(red: 0.82, green: 0.67, blue: 0.31)
    static func stage(_ kind: String) -> Color {
        switch kind { case "DEEP": return purple; case "REM": return blue; case "AWAKE", "RESTLESS": return coral; default: return green }
    }
}

struct DashboardView: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    private static let appIcon: NSImage? = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) }
    var body: some View {
        VStack(spacing: 0) {
            header
            if store.isDemo { demoBanner }
            if let error = store.error ?? store.auth.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { store.error = nil; store.auth.error = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Dismiss error")
                }.font(.system(size: 11)).foregroundStyle(Palette.coral).padding(12)
                    .background(Palette.coral.opacity(0.08))
            }
            if store.isConnected || store.isDemo || store.tab == .settings {
                navigation
                ScrollView {
                    VStack(spacing: 10) {
                        switch store.tab {
                        case .overview: overview
                        case .sleep: sleepDetail
                        case .vitals: vitals
                        case .settings: SettingsView(store: store)
                        }
                    }.padding(16)
                }.scrollIndicators(.hidden)
            } else {
                welcome
            }
            footer
        }
        .frame(width: 404, height: 700)
        .background(scheme == .dark ? Color(red: 0.067, green: 0.086, blue: 0.078) : Color(red: 0.95, green: 0.96, blue: 0.945))
        .tint(scheme == .dark ? Palette.green : Color(red: 0.15, green: 0.43, blue: 0.31))
    }
    private var header: some View {
        HStack(spacing: 11) {
            Group {
                if let icon = Self.appIcon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                        .frame(width: 46, height: 46).frame(width: 39, height: 39)
                } else {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 21, weight: .medium)).foregroundStyle(Palette.green)
                        .frame(width: 39, height: 39).background(Palette.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Air Stats").font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("A LITTLE CLOSER TO YOURSELF").font(.system(size: 8, weight: .medium)).tracking(1.5).foregroundStyle(.secondary)
            }
            Spacer()
            Button { store.tab = store.tab == .settings ? .overview : .settings } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 15))
                    .frame(width: 30, height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.secondary).help("Settings").accessibilityLabel("Settings")
        }.padding(.horizontal, 19).padding(.top, 18).padding(.bottom, 16)
    }
    private var navigation: some View {
        HStack(spacing: 4) {
            ForEach([DashboardTab.overview, .sleep, .vitals], id: \.self) { tab in
                Button { store.tab = tab } label: {
                    Text(tab.rawValue).font(.system(size: 12, weight: store.tab == tab ? .semibold : .regular))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(store.tab == tab ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(store.tab == tab ? .primary : .secondary)
                    .accessibilityAddTraits(store.tab == tab ? .isSelected : [])
            }
        }.padding(4).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 16)
    }
    private var demoBanner: some View {
        HStack {
            Image(systemName: "sparkles")
            Text("Preview · sample data").fontWeight(.medium)
            Spacer()
            Button("Exit preview") { store.endPreview() }.buttonStyle(.plain).underline()
        }.font(.system(size: 11)).foregroundStyle(Palette.gold).padding(.horizontal, 18).padding(.vertical, 10)
            .background(Palette.gold.opacity(0.10)).padding(.bottom, 10)
    }
    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().stroke(Palette.green.opacity(0.08), lineWidth: 1).frame(width: 152, height: 152)
                Circle().stroke(Palette.green.opacity(0.15), lineWidth: 1).frame(width: 115, height: 115)
                Image(systemName: "heart.text.clipboard").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(Palette.green)
            }
            VStack(spacing: 10) {
                Text("Your rhythm.\nOne glance away.")
                    .font(.system(size: 29, weight: .medium, design: .rounded)).multilineTextAlignment(.center)
                Text("Sleep, heart rate, and daily movement.\nA quiet home for your Fitbit in the menu bar.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
            }
            VStack(spacing: 12) {
                Button { store.connect() } label: {
                    HStack(spacing: 9) {
                        if store.auth.isSigningIn { ProgressView().controlSize(.small) }
                        else { Image(systemName: "person.crop.circle") }
                        Text(store.auth.isSigningIn ? "Waiting for Google…" : "Connect with Google").fontWeight(.semibold)
                    }.frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).disabled(store.auth.isSigningIn)
                if store.auth.isSigningIn {
                    Button("Cancel sign-in") { store.auth.cancelSignIn() }.buttonStyle(.plain).foregroundStyle(.secondary)
                } else {
                    Button("Take a look around") { store.preview() }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }.font(.system(size: 12)).padding(.horizontal, 30)
            Text("Read-only access. Credentials stay in Keychain.\nYour health data stays on this Mac.")
                .font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(3)
            Spacer()
        }.padding(.horizontal, 18).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var overview: some View {
        Group {
            HStack {
                Text(store.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                    .font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                if store.isRefreshing { ProgressView().controlSize(.mini) }
                else { Circle().fill(store.isDemo || store.snapshot.hasData ? Palette.green : Color.secondary).frame(width: 5, height: 5) }
            }.padding(.horizontal, 2)
            sleepSummary
            heartCard
            HStack(spacing: 12) {
                compactMetric("Steps today", icon: "figure.walk", value: store.snapshot.steps.map { Int($0).formatted() } ?? "—", unit: "steps", color: Palette.gold)
                compactMetric("Heart rate variability", icon: "waveform.path", value: number(HealthSnapshot.latest(store.snapshot.hrv)?.value), unit: "ms", color: Palette.green,
                              caption: HealthSnapshot.latest(store.snapshot.hrv)?.day)
            }
            scoreAvailability
            if !store.snapshot.issues.isEmpty {
                Button { store.tab = .settings } label: {
                    Label("\(store.snapshot.issues.count) data sources need attention", systemImage: "exclamationmark.circle")
                        .font(.system(size: 10)).foregroundStyle(Palette.gold)
                }.buttonStyle(.plain)
            }
        }
    }
    private var sleepSummary: some View {
        Surface {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel(title: "Latest sleep", symbol: "moon", color: Palette.purple)
                    Text(HealthDate.duration(store.snapshot.latestSleep?.minutesAsleep))
                        .font(.system(size: 31, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(store.snapshot.latestSleep.map { "Night ending \($0.day)" } ?? "Your next night will appear after sync")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    ScoreRing(value: store.snapshot.latestSleep?.efficiency, color: Palette.purple)
                    Text("EFFICIENCY").font(.system(size: 8, weight: .medium)).tracking(1).foregroundStyle(.secondary)
                }.help("Time asleep ÷ time in bed. This is not Fitbit's Sleep Score.")
            }
        }
    }
    private var heartCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(title: "Heart rate", symbol: "heart", color: Palette.coral)
                    Spacer()
                    Text(store.snapshot.latestHeart == nil ? "AWAITING SYNC" : "LATEST SYNCED")
                        .font(.system(size: 8, weight: .medium)).tracking(0.8).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(number(store.snapshot.latestHeart?.bpm)).font(.system(size: 33, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("bpm").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(store.age(store.snapshot.latestHeart?.time)).foregroundStyle(store.heartIsStale ? Palette.gold : Color.secondary)
                        Text("Last 24 hours").foregroundStyle(.secondary)
                    }.font(.system(size: 9))
                }
                HeartChart(samples: store.snapshot.heart, color: Palette.coral).frame(height: 35)
            }
        }
    }
    private var scoreAvailability: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle.dashed").font(.system(size: 26, weight: .ultraLight)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text("Sleep Score & Readiness").font(.system(size: 11, weight: .medium))
                Text("Google doesn't share these scores through its API. Check them in the Fitbit / Google Health app.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
            }
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
    }
    private var sleepDetail: some View {
        Group {
            sleepSummary
            Surface {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Your last 7 nights", symbol: "chart.bar", color: Palette.purple)
                    if store.snapshot.sleep.isEmpty { EmptyMetric("Sleep history appears after your tracker syncs.") }
                    else {
                        Chart(mainNights) { night in
                            if let minutes = night.minutesAsleep {
                                BarMark(x: .value("Night ending", String(night.day.suffix(5))), y: .value("Hours asleep", minutes / 60))
                                    .foregroundStyle(Palette.purple.gradient).cornerRadius(4)
                                    .accessibilityLabel("\(night.day), \(HealthDate.duration(minutes))")
                            }
                        }.chartYAxis { AxisMarks(position: .leading, values: [0, 4, 8]) }.frame(height: 110)
                    }
                }
            }
            if let sleep = store.snapshot.latestSleep {
                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(title: "Sleep stages", symbol: "moon.zzz", color: Palette.purple)
                        if !sleep.processed { EmptyMetric("Google is still processing this sleep session.") }
                        if !sleep.stages.isEmpty {
                            Chart(sleep.stages) { stage in
                                RectangleMark(xStart: .value("Start", stage.start), xEnd: .value("End", stage.end), y: .value("Stage", stage.kind))
                                    .foregroundStyle(Palette.stage(stage.kind)).cornerRadius(2)
                            }.chartXAxis { AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                                AxisValueLabel(format: .dateTime.hour().minute())
                            } }.chartYAxis { AxisMarks(position: .leading) }
                                .frame(height: 105)
                        }
                        ForEach(["DEEP", "LIGHT", "REM", "AWAKE", "ASLEEP", "RESTLESS"], id: \.self) { kind in
                            if let minutes = sleep.stageMinutes[kind] {
                                HStack {
                                    Circle().fill(Palette.stage(kind)).frame(width: 6, height: 6)
                                    Text(kind.capitalized).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(HealthDate.duration(minutes)).monospacedDigit()
                                }.font(.system(size: 11))
                            }
                        }
                        if sleep.stageMinutes.isEmpty && sleep.stages.isEmpty { EmptyMetric("No stage breakdown was supplied for this session.") }
                    }
                }
            }
            scoreAvailability
        }
    }
    private var mainNights: [SleepSession] {
        let groups = Dictionary(grouping: store.snapshot.sleep, by: \.day)
        return groups.values.compactMap { group in group.first(where: \.isMain) ?? group.max(by: { $0.minutesInBed < $1.minutesInBed }) }
            .sorted { $0.day < $1.day }.suffix(7).map { $0 }
    }
    private var vitals: some View {
        Group {
            heartCard
            Text("Heart rate updates after your tracker syncs to your phone. This is not a live Bluetooth stream.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
            HStack(spacing: 12) {
                dailyCard("Resting heart rate", symbol: "heart", values: store.snapshot.restingHeart, unit: "bpm", color: Palette.coral)
                dailyCard("Heart rate variability", symbol: "waveform.path", values: store.snapshot.hrv, unit: "ms", color: Palette.green)
            }
            HStack(spacing: 12) {
                dailyCard("Blood oxygen", symbol: "drop", values: store.snapshot.oxygen, unit: "%", color: Palette.blue, digits: 1)
                dailyCard("Breathing rate", symbol: "lungs", values: store.snapshot.respiration, unit: "/min", color: Palette.purple, digits: 1)
            }
            Surface {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(title: "Skin temperature", symbol: "thermometer.medium", color: Palette.gold)
                        Text("Change from your 30-day baseline").font(.system(size: 9)).foregroundStyle(.secondary)
                        Text(HealthSnapshot.latest(store.snapshot.temperature)?.day ?? "No measurement yet").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(HealthSnapshot.latest(store.snapshot.temperature).map { String(format: "%+.1f°", $0.value) } ?? "—")
                        .font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit()
                }
            }
            Text("Availability depends on your device, permissions, and recorded nights.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
    private func dailyCard(_ title: String, symbol: String, values: [DailyMetric], unit: String, color: Color, digits: Int = 0) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: title, symbol: symbol, color: color)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(number(HealthSnapshot.latest(values)?.value, digits: digits)).font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(unit).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if !values.isEmpty {
                    Chart(values) { point in
                        LineMark(x: .value("Date", point.day), y: .value("Value", point.value)).foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.5))
                        PointMark(x: .value("Date", point.day), y: .value("Value", point.value)).foregroundStyle(color).symbolSize(8)
                    }.chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: .automatic(includesZero: false)).frame(height: 25)
                } else { Color.clear.frame(height: 25) }
                Text(HealthSnapshot.latest(values)?.day ?? "No measurement yet").font(.system(size: 9)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func compactMetric(_ title: String, icon: String, value: String, unit: String, color: Color, caption: String? = nil) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 9) {
                SectionLabel(title: title, symbol: icon, color: color)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(unit).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                if let caption { Text(caption).font(.system(size: 9)).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, minHeight: 49, alignment: .topLeading)
        }
    }
    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(spacing: 7) {
                if let device = store.snapshot.devices.first {
                    Image(systemName: "applewatch.side.right").foregroundStyle(.secondary)
                    Text(device.name).lineLimit(1)
                    if let battery = device.battery { Text("\(Int(battery))%").foregroundStyle(.secondary) }
                    Spacer(minLength: 2)
                    Text("Synced \(store.age(device.lastSync).lowercased())").foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Image(systemName: "lock.shield").foregroundStyle(.secondary)
                    Text(store.isConnected ? "Checked \(store.age(store.snapshot.fetchedAt).lowercased())" : "Made for your menu bar").foregroundStyle(.secondary)
                    Spacer()
                }
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise").frame(width: 24, height: 26) }
                    .disabled(!store.isConnected || store.isRefreshing || store.isDemo).buttonStyle(.plain)
                    .help("Refresh now").accessibilityLabel("Refresh now").keyboardShortcut("r", modifiers: .command)
            }.font(.system(size: 9)).padding(.horizontal, 16).padding(.vertical, 8)
        }
    }
    private func number(_ value: Double?, digits: Int = 0) -> String { value.map { String(format: "%.*f", digits, $0) } ?? "—" }
}

struct Surface<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(scheme == .dark ? Color.white.opacity(0.035) : Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(scheme == .dark ? Color.white.opacity(0.065) : .clear, lineWidth: 0.5))
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.025), radius: 4, y: 2)
    }
}

struct SectionLabel: View {
    var title: String
    var symbol: String
    var color: Color
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.9)
        }
    }
}

struct ScoreRing: View {
    var value: Double?
    var color: Color
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.13), lineWidth: 5)
            Circle().trim(from: 0, to: min(1, max(0, (value ?? 0) / 100)))
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            Text(value.map { "\(Int($0))%" } ?? "—").font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit()
        }.frame(width: 65, height: 65).padding(3)
            .accessibilityElement(children: .ignore).accessibilityLabel("Sleep efficiency").accessibilityValue(value.map { "\(Int($0)) percent" } ?? "Unavailable")
    }
}

struct HeartChart: View {
    var samples: [HeartSample]
    var color: Color
    /// Five-minute averages keep a full day light enough for a menu-bar popover.
    private var buckets: [HeartSample] {
        let grouped: [Int: [HeartSample]] = Dictionary(grouping: samples) { Int($0.time.timeIntervalSince1970 / 300) }
        let averages: [HeartSample] = grouped.map { entry in
            let total: Double = entry.value.reduce(0.0) { $0 + $1.bpm }
            let time = Date(timeIntervalSince1970: Double(entry.key * 300))
            return HeartSample(time: time, bpm: total / Double(entry.value.count))
        }
        return averages.sorted { $0.time < $1.time }
    }
    var body: some View {
        if samples.isEmpty {
            EmptyMetric("No synced heart-rate readings yet.")
        } else {
            Chart(buckets) { sample in
                PointMark(x: .value("Time", sample.time), y: .value("Heart rate", sample.bpm))
                    .foregroundStyle(color).symbolSize(9)
            }.chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: .automatic(includesZero: false))
                .accessibilityLabel("Heart rate over the last 24 hours, five-minute averages")
        }
    }
}

struct EmptyMetric: View {
    var message: String
    init(_ message: String) { self.message = message }
    var body: some View {
        Text(message).font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
    }
}
