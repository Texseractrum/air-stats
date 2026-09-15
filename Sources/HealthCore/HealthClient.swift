import Foundation

public enum HealthAPIError: LocalizedError {
    case http(Int, String), pagination, invalidResponse
    /// Google reports the actionable cause in `{"error":{"message":…,"details":[{"reason":…}]}}`,
    /// so the status code alone is never enough to tell someone what to do next.
    static func detail(_ body: String) -> (reason: String?, message: String?) {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(body.utf8)) else { return (nil, nil) }
        let error = value["error"]
        return (error["details"].array.compactMap { $0["reason"].string }.first, error["message"].string)
    }
    public var errorDescription: String? {
        if case .http(_, let body) = self, Self.detail(body).reason == "ACCOUNT_NOT_LINKED" {
            return "This Google account isn't linked to Google Health, so it has no Fitbit data to read. Link it at fitbit.google.com, or reconnect Air Stats with the account that holds your Fitbit data."
        }
        switch self {
        case .http(401, _): return "Google access expired. Reconnect your account in Settings."
        case .http(403, let reason):
            if reason.contains("SERVICE_DISABLED") { return "Enable Google Health API in your Google Cloud project." }
            return "Google denied access. Reconnect and allow this data permission; check the project's test-user list."
        case .http(429, _): return "Google's request limit was reached. Wait a few minutes before refreshing."
        case .http(let status, let body):
            if let message = Self.detail(body).message { return "Google Health returned HTTP \(status): \(message)" }
            return "Google Health returned HTTP \(status). Try again later."
        case .pagination: return "Google returned an incomplete data range. Try refreshing again."
        case .invalidResponse: return "Google returned an unexpected response."
        }
    }
}

public enum HealthQuery {
    public static let types = ["heart-rate", "sleep", "steps", "daily-resting-heart-rate", "daily-heart-rate-variability",
                               "daily-oxygen-saturation", "daily-respiratory-rate", "daily-sleep-temperature-derivations"]
    public static func filter(type: String, now: Date, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let week = calendar.date(byAdding: .day, value: -6, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let snake = type.replacingOccurrences(of: "-", with: "_")
        if type.hasPrefix("daily-") {
            return "\(snake).date >= \"\(HealthDate.day(week, calendar: calendar))\" AND \(snake).date < \"\(HealthDate.day(tomorrow, calendar: calendar))\""
        }
        let field: String, start: Date
        switch type {
        case "sleep": field = "sleep.interval.end_time"; start = week
        case "heart-rate": field = "heart_rate.sample_time.physical_time"; start = now.addingTimeInterval(-24 * 3600)
        default: field = "\(snake).interval.start_time"; start = today
        }
        return "\(field) >= \"\(HealthDate.timestamp(start))\" AND \(field) < \"\(HealthDate.timestamp(now))\""
    }
    public static func url(type: String, now: Date, pageToken: String? = nil, calendar: Calendar = .current) -> URL {
        var url = URLComponents(string: "https://health.googleapis.com/v4/users/me/dataTypes/\(type)/dataPoints:reconcile")!
        url.queryItems = [URLQueryItem(name: "filter", value: filter(type: type, now: now, calendar: calendar)),
                         URLQueryItem(name: "dataSourceFamily", value: "users/me/dataSourceFamilies/google-wearables"),
                         URLQueryItem(name: "pageSize", value: type == "sleep" ? "25" : "10000")]
        if let pageToken { url.queryItems!.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return url.url!
    }
}

public final class HealthClient: @unchecked Sendable {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        if let session { self.session = session } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 90
            self.session = URLSession(configuration: configuration)
        }
    }
    private func get(_ url: URL, token: String) async throws -> JSONValue {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw HealthAPIError.invalidResponse }
        guard response.statusCode == 200 else {
            throw HealthAPIError.http(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
    public func points(type: String, token: String, now: Date, calendar: Calendar = .current) async throws -> [JSONValue] {
        var points: [JSONValue] = [], pageToken: String?, seen = Set<String>()
        repeat {
            let response = try await get(HealthQuery.url(type: type, now: now, pageToken: pageToken, calendar: calendar), token: token)
            points += response["dataPoints"].array
            pageToken = response["nextPageToken"].string.flatMap { $0.isEmpty ? nil : $0 }
            if let pageToken, !seen.insert(pageToken).inserted || seen.count > 100 { throw HealthAPIError.pagination }
        } while pageToken != nil
        return points
    }
    public func snapshot(token: String, now: Date = Date()) async throws -> HealthSnapshot {
        var result = HealthSnapshot()
        var payloads: [String: [JSONValue]] = [:]
        await withTaskGroup(of: (String, [JSONValue]?, String?).self) { group in
            for type in HealthQuery.types {
                group.addTask {
                    do { return (type, try await self.points(type: type, token: token, now: now), nil) }
                    catch { return (type, nil, error.localizedDescription) }
                }
            }
            group.addTask {
                do {
                    var devices: [JSONValue] = [], next: String?, seen = Set<String>()
                    repeat {
                        var url = URLComponents(string: "https://health.googleapis.com/v4/users/me/pairedDevices")!
                        url.queryItems = [URLQueryItem(name: "pageSize", value: "100")]
                        if let next { url.queryItems!.append(URLQueryItem(name: "pageToken", value: next)) }
                        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
                        let response = try await self.get(url.url!, token: token)
                        devices += response["pairedDevices"].array
                        next = response["nextPageToken"].string.flatMap { $0.isEmpty ? nil : $0 }
                        if let next, !seen.insert(next).inserted || seen.count > 100 { throw HealthAPIError.pagination }
                    } while next != nil
                    return ("devices", devices, nil)
                } catch { return ("devices", nil, error.localizedDescription) }
            }
            for await (type, points, error) in group {
                if let points { payloads[type] = points }
                if let error { result.issues[type] = error }
            }
        }
        try Task.checkCancellation()
        result.fetchedAt = now
        result.heart = HealthParser.heart(payloads["heart-rate"] ?? [])
        result.sleep = HealthParser.sleep(payloads["sleep"] ?? [])
        result.steps = HealthParser.steps(payloads["steps"] ?? [])
        result.restingHeart = HealthParser.daily(payloads["daily-resting-heart-rate"] ?? [], key: "dailyRestingHeartRate", field: "beatsPerMinute")
        result.hrv = HealthParser.daily(payloads["daily-heart-rate-variability"] ?? [], key: "dailyHeartRateVariability", field: "averageHeartRateVariabilityMilliseconds")
        result.oxygen = HealthParser.daily(payloads["daily-oxygen-saturation"] ?? [], key: "dailyOxygenSaturation", field: "averagePercentage")
        result.respiration = HealthParser.daily(payloads["daily-respiratory-rate"] ?? [], key: "dailyRespiratoryRate", field: "breathsPerMinute")
        result.temperature = (payloads["daily-sleep-temperature-derivations"] ?? []).compactMap { point in
            let value = point["dailySleepTemperatureDerivations"]
            guard let day = HealthDate.civilDay(value["date"]), let actual = value["nightlyTemperatureCelsius"].number,
                  let baseline = value["baselineTemperatureCelsius"].number else { return nil }
            return DailyMetric(day: day, value: actual - baseline)
        }.sorted { $0.day < $1.day }
        result.devices = (payloads["devices"] ?? []).compactMap { device in
            guard device["deviceType"].string != "SCALE", let name = device["deviceVersion"].string else { return nil }
            return TrackerDevice(id: device["name"].string ?? name, name: name,
                                 battery: device["batteryLevel"].number, lastSync: HealthDate.parse(device["lastSyncTime"].string))
        }
        return result
    }
}
