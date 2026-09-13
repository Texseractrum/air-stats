import Foundation
import HealthCore

/// Explicit, opt-in sample data; never substituted for missing account data.
enum DemoData {
    static func snapshot(now: Date) -> HealthSnapshot {
        var result = HealthSnapshot()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        result.fetchedAt = now
        let pattern: [Double] = [61, 63, 62, 60, 62, 65, 63, 62, 64, 63, 61, 64, 68, 66, 65, 63, 64, 62, 61, 64]
        result.heart = (0..<240).map { (index: Int) -> HeartSample in
            let offset: TimeInterval = Double(index - 240) * 60
            let activityIncrease: Double = (index > 115 && index < 160) ? 16 : 0
            let bpm: Double = pattern[index % pattern.count] + activityIncrease
            return HeartSample(time: now.addingTimeInterval(offset), bpm: bpm)
        }
        let nights: [Double] = [425, 402, 461, 437, 414, 489, 462]
        for index in 0..<7 {
            let day = calendar.date(byAdding: .day, value: index - 6, to: today)!
            let end = calendar.date(byAdding: .hour, value: 8, to: day)!
            let start = end.addingTimeInterval(-8.4 * 3600)
            let dayString = HealthDate.day(day)
            let kinds = ["LIGHT", "DEEP", "LIGHT", "REM", "AWAKE", "LIGHT", "DEEP", "REM", "LIGHT", "AWAKE", "REM", "LIGHT"]
            let stages = kinds.enumerated().map { index, kind in
                SleepStage(start: start.addingTimeInterval(Double(index) * 2520),
                           end: start.addingTimeInterval(Double(index + 1) * 2520), kind: kind)
            }
            result.sleep.append(SleepSession(start: start, end: end, day: dayString, minutesAsleep: nights[index], stages: stages,
                                              stageMinutes: ["DEEP": 86, "LIGHT": nights[index] - 190, "REM": 104, "AWAKE": 504 - nights[index]], isMain: true))
            result.hrv.append(DailyMetric(day: dayString, value: [42, 46, 44, 51, 49, 54, 52][index]))
            result.restingHeart.append(DailyMetric(day: dayString, value: [59, 58, 60, 57, 58, 56, 57][index]))
            result.oxygen.append(DailyMetric(day: dayString, value: 97.4))
            result.respiration.append(DailyMetric(day: dayString, value: 14.2))
            result.temperature.append(DailyMetric(day: dayString, value: 0.2))
        }
        result.steps = 6842
        result.devices = [TrackerDevice(id: "demo", name: "Fitbit Air", battery: 78, lastSync: now.addingTimeInterval(-120))]
        return result
    }
}
