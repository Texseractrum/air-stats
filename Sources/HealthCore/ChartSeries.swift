import Foundation

/// Plotting preparation shared by the native charts and their regression tests.
/// A new series starts at every missing interval, so a line never bridges a gap.
public struct TrendPoint: Identifiable, Sendable {
    public var time: Date
    public var value: Double
    public var series: Int
    public var id: Date { time }
}

public enum ChartSeries {
    public static func heart(_ samples: [HeartSample]) -> [TrendPoint] {
        let valid = samples.filter { $0.bpm.isFinite && $0.bpm > 0 }
        let groups = Dictionary(grouping: valid) { floor($0.time.timeIntervalSince1970 / 300) }
        var result: [TrendPoint] = []
        var series = 0
        for bucket in groups.keys.sorted() {
            let time = Date(timeIntervalSince1970: bucket * 300)
            if let previous = result.last, time.timeIntervalSince(previous.time) > 300 { series += 1 }
            let readings = groups[bucket]!
            let average = readings.reduce(0.0) { $0 + $1.bpm / Double(readings.count) }
            result.append(TrendPoint(time: time, value: average, series: series))
        }
        return result
    }

    public static func civilDate(_ day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              HealthDate.day(date, calendar: calendar) == day else { return nil }
        return date
    }

    public static func daily(_ values: [DailyMetric], calendar: Calendar = .current) -> [TrendPoint] {
        var days: [Date: Double] = [:]
        for value in values where value.value.isFinite {
            if let date = civilDate(value.day, calendar: calendar) { days[date] = value.value }
        }
        var result: [TrendPoint] = []
        var series = 0
        for date in days.keys.sorted() {
            if let previous = result.last,
               calendar.dateComponents([.day], from: calendar.startOfDay(for: previous.time), to: calendar.startOfDay(for: date)).day != 1 { series += 1 }
            result.append(TrendPoint(time: date, value: days[date]!, series: series))
        }
        return result
    }

    public static func isolatedSeries(_ points: [TrendPoint]) -> Set<Int> {
        Set(Dictionary(grouping: points, by: \.series).filter { $0.value.count == 1 }.keys)
    }

    /// Minimum spans avoid magnifying tiny day-to-day changes into dramatic swings.
    public static func domain(_ values: [Double], minimumSpan: Double, floor: Double? = nil, ceiling: Double? = nil) -> ClosedRange<Double> {
        let finite = values.filter(\.isFinite)
        let low = finite.min() ?? floor ?? 0
        let high = finite.max() ?? low
        let span = max(minimumSpan, (high - low) * 1.25)
        var lower = (low + high - span) / 2
        var upper = lower + span
        if let floor, lower < floor { lower = min(floor, low); upper = max(upper, lower + span) }
        if let ceiling, upper > ceiling { upper = max(ceiling, high); lower = min(lower, upper - span) }
        if let floor { lower = max(min(floor, low), lower) }
        return lower...max(lower + 0.001, upper)
    }
}
