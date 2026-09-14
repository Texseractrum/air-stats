import Foundation

/// The REST API encodes int64 values as strings and ordinary numbers as JSON numbers.
public enum JSONValue: Decodable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public subscript(_ key: String) -> JSONValue {
        if case .object(let object) = self { return object[key] ?? .null }
        return .null
    }
    public var array: [JSONValue] { if case .array(let value) = self { return value }; return [] }
    public var string: String? { if case .string(let value) = self { return value }; return nil }
    public var number: Double? {
        switch self {
        case .number(let value): return value.isFinite ? value : nil
        case .string(let value): guard let number = Double(value), number.isFinite else { return nil }; return number
        default: return nil
        }
    }
    public var bool: Bool? { if case .bool(let value) = self { return value }; return nil }
}

public enum HealthDate {
    public static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
    public static func timestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    public static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    public static func civilDay(_ value: JSONValue) -> String? {
        guard let year = value["year"].number, let month = value["month"].number,
              let day = value["day"].number, (1...12).contains(Int(month)), (1...31).contains(Int(day)) else { return nil }
        return String(format: "%04d-%02d-%02d", Int(year), Int(month), Int(day))
    }
    public static func duration(_ minutes: Double?) -> String {
        guard let minutes else { return "—" }
        let rounded = max(0, Int(minutes.rounded()))
        return "\(rounded / 60)h \(rounded % 60)m"
    }
}

public struct HeartSample: Identifiable, Sendable {
    public var time: Date
    public var bpm: Double
    public var id: Date { time }
    public init(time: Date, bpm: Double) { self.time = time; self.bpm = bpm }
}

public struct DailyMetric: Identifiable, Sendable {
    public var day: String
    public var value: Double
    public var id: String { day }
    public init(day: String, value: Double) { self.day = day; self.value = value }
}

public struct SleepStage: Identifiable, Sendable {
    public var start: Date
    public var end: Date
    public var kind: String
    public var id: String { "\(start.timeIntervalSince1970)-\(kind)" }
    public var minutes: Double { max(0, end.timeIntervalSince(start) / 60) }
    public init(start: Date, end: Date, kind: String) { self.start = start; self.end = end; self.kind = kind }
}

public struct SleepSession: Identifiable, Sendable {
    public var start: Date
    public var end: Date
    public var day: String
    public var minutesAsleep: Double?
    public var stages: [SleepStage]
    public var stageMinutes: [String: Double]
    public var isMain: Bool
    public var processed: Bool
    public var id: Date { start }
    public var minutesInBed: Double { end.timeIntervalSince(start) / 60 }
    /// A duration ratio, never Fitbit's proprietary Sleep Score.
    public var efficiency: Double? {
        guard processed, let minutesAsleep, minutesInBed > 0,
              minutesAsleep >= 0, minutesAsleep <= minutesInBed else { return nil }
        return (minutesAsleep / minutesInBed * 100).rounded()
    }
    public init(start: Date, end: Date, day: String, minutesAsleep: Double?, stages: [SleepStage],
                stageMinutes: [String: Double], isMain: Bool, processed: Bool = true) {
        self.start = start; self.end = end; self.day = day; self.minutesAsleep = minutesAsleep
        self.stages = stages; self.stageMinutes = stageMinutes; self.isMain = isMain; self.processed = processed
    }
}

public struct TrackerDevice: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var battery: Double?
    public var lastSync: Date?
    public init(id: String, name: String, battery: Double?, lastSync: Date?) {
        self.id = id; self.name = name; self.battery = battery; self.lastSync = lastSync
    }
}

public struct HealthSnapshot: Sendable {
    public var fetchedAt: Date?
    public var heart: [HeartSample] = []
    public var sleep: [SleepSession] = []
    public var restingHeart: [DailyMetric] = []
    public var hrv: [DailyMetric] = []
    public var oxygen: [DailyMetric] = []
    public var respiration: [DailyMetric] = []
    public var temperature: [DailyMetric] = []
    public var steps: Double?
    public var devices: [TrackerDevice] = []
    public var issues: [String: String] = [:]
    public init() {}
    public var latestHeart: HeartSample? { heart.max(by: { $0.time < $1.time }) }
    public var latestSleep: SleepSession? {
        let main = sleep.filter(\.isMain)
        return (main.isEmpty ? sleep : main).max(by: { $0.end < $1.end })
    }
    public var representativeSleepByDay: [SleepSession] {
        Dictionary(grouping: sleep, by: \.day).values.compactMap { sessions in
            sessions.first(where: \.isMain) ?? sessions.max(by: { $0.minutesInBed < $1.minutesInBed })
        }.sorted { $0.day < $1.day }
    }
    public var hasData: Bool {
        !heart.isEmpty || !sleep.isEmpty || !restingHeart.isEmpty || !hrv.isEmpty || !oxygen.isEmpty || steps != nil
    }
    public static func latest(_ values: [DailyMetric]) -> DailyMetric? { values.max(by: { $0.day < $1.day }) }
}

public enum HealthParser {
    public static func heart(_ points: [JSONValue]) -> [HeartSample] {
        var unique: [Date: HeartSample] = [:]
        for point in points {
            let value = point["heartRate"]
            if let time = HealthDate.parse(value["sampleTime"]["physicalTime"].string),
               let bpm = value["beatsPerMinute"].number, bpm > 0 {
                unique[time] = HeartSample(time: time, bpm: bpm)
            }
        }
        return unique.values.sorted { $0.time < $1.time }
    }
    public static func daily(_ points: [JSONValue], key: String, field: String) -> [DailyMetric] {
        points.compactMap { point in
            guard let day = HealthDate.civilDay(point[key]["date"]), let value = point[key][field].number else { return nil }
            return DailyMetric(day: day, value: value)
        }.sorted { $0.day < $1.day }
    }
    public static func sleep(_ points: [JSONValue]) -> [SleepSession] {
        points.compactMap { point in
            let sleep = point["sleep"], interval = sleep["interval"]
            guard let start = HealthDate.parse(interval["startTime"].string),
                  let end = HealthDate.parse(interval["endTime"].string), end > start else { return nil }
            let offset = interval["endUtcOffset"].string.flatMap { Double($0.replacingOccurrences(of: "s", with: "")) } ?? 0
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: Int(offset)) ?? .gmt
            let day = HealthDate.civilDay(interval["civilEndTime"]["date"]) ?? HealthDate.day(end, calendar: calendar)
            let stages = sleep["stages"].array.compactMap { stage -> SleepStage? in
                guard let from = HealthDate.parse(stage["startTime"].string), let to = HealthDate.parse(stage["endTime"].string),
                      to > from, let kind = stage["type"].string else { return nil }
                return SleepStage(start: from, end: to, kind: kind)
            }.sorted { $0.start < $1.start }
            // Use the server's finalized summary: short awakenings overlap stages and must not be summed twice.
            var stageMinutes: [String: Double] = [:]
            for stage in sleep["summary"]["stagesSummary"].array {
                if let kind = stage["type"].string, let minutes = stage["minutes"].number { stageMinutes[kind] = minutes }
            }
            return SleepSession(start: start, end: end, day: day,
                                minutesAsleep: sleep["summary"]["minutesAsleep"].number,
                                stages: stages, stageMinutes: stageMinutes,
                                isMain: sleep["metadata"]["mainSleep"].bool ?? false,
                                processed: sleep["metadata"]["processed"].bool ?? true)
        }.sorted { $0.end < $1.end }
    }
    public static func steps(_ points: [JSONValue]) -> Double? {
        let values = points.compactMap { $0["steps"]["count"].number }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}
