import Foundation
import HealthCore

/// A local, stdio-only MCP server. It reads the same Keychain entries as Air Stats
/// and never prints OAuth credentials or writes health readings to disk.
enum AgentMCP {
    static func run() -> Never {
        let server = Server()
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8),
                  let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                write(["jsonrpc": "2.0", "id": NSNull(),
                       "error": ["code": -32700, "message": "Parse error"]])
                continue
            }
            if let response = server.response(to: request) { write(response) }
        }
        exit(0)
    }

    private static func write(_ response: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(response),
              let data = try? JSONSerialization.data(withJSONObject: response) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0a]))
    }

    private final class Server {
        private var cachedSnapshot: (date: Date, value: HealthSnapshot)?

        func response(to request: [String: Any]) -> [String: Any]? {
            let id = request["id"]
            guard let method = request["method"] as? String else {
                return error(id: id ?? NSNull(), code: -32600, message: "Invalid request")
            }
            if id == nil { return nil }
            switch method {
            case "initialize":
                let params = request["params"] as? [String: Any]
                let requestedVersion = params?["protocolVersion"] as? String
                return result(id: id!, value: [
                    "protocolVersion": requestedVersion ?? "2025-11-25",
                    "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": [
                        "name": "airstats-health",
                        "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
                    ],
                    "instructions": "Read-only access to the user's latest Google/Fitbit wearable snapshot. Preserve measurement dates and sync limitations in every interpretation."
                ])
            case "ping":
                return result(id: id!, value: [:])
            case "tools/list":
                return result(id: id!, value: ["tools": tools])
            case "tools/call":
                return callTool(id: id!, params: request["params"] as? [String: Any])
            default:
                return error(id: id!, code: -32601, message: "Method not found")
            }
        }

        private var tools: [[String: Any]] {
            let annotations: [String: Any] = [
                "readOnlyHint": true,
                "destructiveHint": false,
                "idempotentHint": true,
                "openWorldHint": true
            ]
            return [
                [
                    "name": "get_health_summary",
                    "title": "Get Air Stats health summary",
                    "description": "Fetch an analysis-ready summary of the user's latest synced Fitbit/Google wearable data: heart rate, sleep, steps, HRV, resting heart rate, oxygen saturation, breathing rate, temperature deviation, devices, dates, and source errors. Use this first for personal health, recovery, sleep, activity, or trend questions. The data is read-only and is not a diagnosis.",
                    "inputSchema": ["type": "object", "additionalProperties": false],
                    "annotations": annotations
                ],
                [
                    "name": "get_health_metric",
                    "title": "Get one Air Stats health metric",
                    "description": "Fetch the recent underlying points for one personal Fitbit/Google wearable metric after get_health_summary, when the question needs exact values or dates.",
                    "inputSchema": [
                        "type": "object",
                        "properties": [
                            "metric": [
                                "type": "string",
                                "enum": ["heart_rate", "sleep", "steps", "resting_heart_rate", "hrv", "oxygen_saturation", "breathing_rate", "temperature_deviation", "devices"],
                                "description": "The metric to retrieve."
                            ]
                        ],
                        "required": ["metric"],
                        "additionalProperties": false
                    ],
                    "annotations": annotations
                ]
            ]
        }

        private func callTool(id: Any, params: [String: Any]?) -> [String: Any] {
            guard let name = params?["name"] as? String else {
                return error(id: id, code: -32602, message: "Missing tool name")
            }
            do {
                let payload: [String: Any]
                switch name {
                case "get_health_summary":
                    let arguments = params?["arguments"] as? [String: Any] ?? [:]
                    guard arguments.isEmpty else {
                        return toolError(id: id, message: "get_health_summary does not accept arguments.")
                    }
                    payload = AgentHealthPayload.summary(try currentSnapshot())
                case "get_health_metric":
                    guard let arguments = params?["arguments"] as? [String: Any],
                          arguments.count == 1,
                          let metric = arguments["metric"] as? String,
                          AgentHealthPayload.supportedMetrics.contains(metric) else {
                        return toolError(id: id, message: "Choose a metric from the get_health_metric schema.")
                    }
                    guard let value = AgentHealthPayload.metric(metric, from: try currentSnapshot()) else {
                        return toolError(id: id, message: "Unknown metric: \(metric).")
                    }
                    payload = value
                default:
                    return error(id: id, code: -32602, message: "Unknown tool: \(name)")
                }
                let text = try AgentHealthPayload.json(payload)
                return result(id: id, value: [
                    "content": [["type": "text", "text": text]],
                    "structuredContent": payload,
                    "isError": false
                ])
            } catch {
                return toolError(id: id, message: error.localizedDescription)
            }
        }

        private func currentSnapshot() throws -> HealthSnapshot {
            if let cachedSnapshot, Date().timeIntervalSince(cachedSnapshot.date) < 60 { return cachedSnapshot.value }
            let box = BlockingResult<HealthSnapshot>()
            Task.detached {
                do {
                    let token = try await AgentTokenProvider().accessToken()
                    box.finish(.success(try await HealthClient().snapshot(token: token)))
                } catch { box.finish(.failure(error)) }
            }
            let snapshot = try box.wait().get()
            cachedSnapshot = (Date(), snapshot)
            return snapshot
        }

        private func result(id: Any, value: [String: Any]) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id, "result": value]
        }

        private func error(id: Any, code: Int, message: String) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
        }

        private func toolError(id: Any, message: String) -> [String: Any] {
            result(id: id, value: [
                "content": [["type": "text", "text": message]],
                "isError": true
            ])
        }
    }
}

private final class BlockingResult<Value>: @unchecked Sendable {
    private let condition = NSCondition()
    private var result: Result<Value, Error>?

    func finish(_ result: Result<Value, Error>) {
        condition.lock()
        self.result = result
        condition.broadcast()
        condition.unlock()
    }

    func wait() -> Result<Value, Error> {
        condition.lock()
        while result == nil { condition.wait() }
        let value = result!
        condition.unlock()
        return value
    }
}

private struct AgentTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiry: Date
}

private final class AgentTokenProvider: @unchecked Sendable {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    func accessToken() async throws -> String {
        guard let configurationData = try Keychain.read("oauth.configuration") else {
            throw OAuthError.message("Air Stats is not connected. Open Air Stats, import your Google Desktop OAuth JSON, and connect your account first.")
        }
        let configuration = try OAuthConfiguration.read(configurationData)
        let account = "tokens.\(configuration.installed.client_id)"
        guard let tokenData = try Keychain.read(account) else {
            throw OAuthError.message("Air Stats is not connected. Open Air Stats and connect your Google account first.")
        }
        var tokens = try JSONDecoder().decode(AgentTokens.self, from: tokenData)
        if tokens.expiry.timeIntervalSinceNow > 60 { return tokens.accessToken }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OAuthPKCE.form([
            "client_id": configuration.installed.client_id,
            "client_secret": configuration.installed.client_secret,
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken
        ])
        let (data, response) = try await session.data(for: request)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let accessToken = json["access_token"].string else {
            if json["error"].string == "invalid_grant" {
                throw OAuthError.message("Google authorization expired or was revoked. Reconnect your account in Air Stats Settings.")
            }
            throw OAuthError.message("Google could not refresh Air Stats access. Open Air Stats Settings and reconnect your account.")
        }
        tokens.accessToken = accessToken
        tokens.expiry = Date().addingTimeInterval(json["expires_in"].number ?? 3600)
        try Keychain.save(try JSONEncoder().encode(tokens), account: account)
        return tokens.accessToken
    }
}

private enum AgentHealthPayload {
    private static let null = NSNull()
    static let supportedMetrics: Set<String> = [
        "heart_rate", "sleep", "steps", "resting_heart_rate", "hrv", "oxygen_saturation",
        "breathing_rate", "temperature_deviation", "devices"
    ]

    static func summary(_ snapshot: HealthSnapshot) -> [String: Any] {
        let heart = snapshot.latestHeart
        let sleep = snapshot.latestSleep
        return [
            "schemaVersion": 1,
            "fetchedAt": date(snapshot.fetchedAt),
            "source": [
                "service": "Google Health API",
                "dataSourceFamily": "google-wearables",
                "heartRateWindow": "last 24 hours",
                "dailyAndSleepWindow": "last 7 days",
                "live": false,
                "notes": [
                    "Readings appear only after the wearable syncs to the phone and Google.",
                    "The stream can include compatible Fitbit and Pixel devices on the same Google account.",
                    "Fitbit Sleep Score and Daily Readiness Score are not exposed by this API."
                ]
            ],
            "latest": [
                "heartRate": heartValue(heart),
                "sleep": optionalSleep(sleep),
                "restingHeartRate": latest(snapshot.restingHeart, unit: "bpm"),
                "heartRateVariability": latest(snapshot.hrv, unit: "ms"),
                "oxygenSaturation": latest(snapshot.oxygen, unit: "percent"),
                "breathingRate": latest(snapshot.respiration, unit: "breaths/min"),
                "temperatureDeviation": latest(snapshot.temperature, unit: "°C from personal baseline")
            ],
            "today": ["steps": number(snapshot.steps), "unit": "steps"],
            "trends": [
                "sleep": snapshot.representativeSleepByDay.map(sleepValue),
                "restingHeartRate": daily(snapshot.restingHeart, unit: "bpm"),
                "heartRateVariability": daily(snapshot.hrv, unit: "ms"),
                "oxygenSaturation": daily(snapshot.oxygen, unit: "percent"),
                "breathingRate": daily(snapshot.respiration, unit: "breaths/min"),
                "temperatureDeviation": daily(snapshot.temperature, unit: "°C from personal baseline")
            ],
            "coverage": [
                "heartRateSamples": snapshot.heart.count,
                "sleepSessions": snapshot.sleep.count,
                "devices": snapshot.devices.count
            ],
            "devices": snapshot.devices.map(deviceValue),
            "sourceErrors": snapshot.issues
        ]
    }

    static func metric(_ name: String, from snapshot: HealthSnapshot) -> [String: Any]? {
        let common: [String: Any] = ["fetchedAt": date(snapshot.fetchedAt), "metric": name]
        let values: Any
        let unit: String
        switch name {
        case "heart_rate":
            unit = "bpm"
            values = snapshot.heart.map { ["measuredAt": iso($0.time), "value": $0.bpm] }
        case "sleep":
            unit = "minutes"
            values = snapshot.sleep.map(sleepValue)
        case "steps":
            unit = "steps"
            values = [["day": HealthDate.day(snapshot.fetchedAt ?? Date()), "value": number(snapshot.steps)]]
        case "resting_heart_rate":
            unit = "bpm"; values = daily(snapshot.restingHeart, unit: unit)
        case "hrv":
            unit = "ms"; values = daily(snapshot.hrv, unit: unit)
        case "oxygen_saturation":
            unit = "percent"; values = daily(snapshot.oxygen, unit: unit)
        case "breathing_rate":
            unit = "breaths/min"; values = daily(snapshot.respiration, unit: unit)
        case "temperature_deviation":
            unit = "°C from personal baseline"; values = daily(snapshot.temperature, unit: unit)
        case "devices":
            unit = "device metadata"; values = snapshot.devices.map(deviceValue)
        default:
            return nil
        }
        return common.merging(["unit": unit, "values": values, "sourceErrors": snapshot.issues]) { _, new in new }
    }

    static func json(_ value: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func latest(_ values: [DailyMetric], unit: String) -> Any {
        guard let value = HealthSnapshot.latest(values) else { return null }
        return ["day": value.day, "value": value.value, "unit": unit]
    }

    private static func heartValue(_ value: HeartSample?) -> Any {
        guard let value else { return null }
        return ["measuredAt": iso(value.time), "beatsPerMinute": value.bpm, "unit": "bpm"]
    }

    private static func optionalSleep(_ value: SleepSession?) -> Any {
        guard let value else { return null }
        return sleepValue(value)
    }

    private static func daily(_ values: [DailyMetric], unit: String) -> [[String: Any]] {
        values.map { ["day": $0.day, "value": $0.value, "unit": unit] }
    }

    private static func sleepValue(_ sleep: SleepSession) -> [String: Any] {
        [
            "day": sleep.day,
            "start": iso(sleep.start),
            "end": iso(sleep.end),
            "minutesAsleep": sleep.minutesAsleep ?? null,
            "minutesInBed": sleep.minutesInBed,
            "durationEfficiencyPercent": sleep.efficiency ?? null,
            "isMainSleep": sleep.isMain,
            "processed": sleep.processed,
            "stageMinutes": sleep.stageMinutes
        ]
    }

    private static func deviceValue(_ device: TrackerDevice) -> [String: Any] {
        [
            "name": device.name,
            "batteryPercent": device.battery ?? null,
            "lastSync": date(device.lastSync)
        ]
    }

    private static func date(_ value: Date?) -> Any { value.map(iso) ?? null }
    private static func number(_ value: Double?) -> Any { value.map { $0 as Any } ?? null }
    private static func iso(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: value)
    }
}
