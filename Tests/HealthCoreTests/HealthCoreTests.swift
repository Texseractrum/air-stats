import XCTest
@testable import HealthCore

final class HealthCoreTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }

    func testInt64StringsAndNumericValuesDoNotTurnMissingIntoZero() throws {
        let value = try json(#"{"int64":"6842","float":52.3,"zero":"0","missing":null,"bool":true,"nan":"NaN"}"#)
        XCTAssertEqual(value["int64"].number, 6842)
        XCTAssertEqual(value["float"].number, 52.3)
        XCTAssertEqual(value["zero"].number, 0)
        XCTAssertNil(value["missing"].number)
        XCTAssertNil(value["absent"].number)
        XCTAssertNil(value["bool"].number)
        XCTAssertNil(value["nan"].number)
        XCTAssertNil(HealthParser.steps([]))
        XCTAssertEqual(HealthParser.steps([try json(#"{"steps":{"count":"0"}}"#)]), 0)
    }

    func testStableReleaseVersionsCompareNumerically() throws {
        XCTAssertLessThan(try XCTUnwrap(ReleaseVersion("v1.9.9")), try XCTUnwrap(ReleaseVersion("1.10.0")))
        XCTAssertEqual(ReleaseVersion("1.0"), ReleaseVersion("v1.0.0"))
        XCTAssertGreaterThan(try XCTUnwrap(ReleaseVersion("2.0.1")), try XCTUnwrap(ReleaseVersion("2.0.0")))
    }

    func testPrereleaseAndMalformedReleaseVersionsAreRejected() {
        for value in ["", "v", "1..0", "1.2-beta", "release-2.0", "1.2.3.4x"] {
            XCTAssertNil(ReleaseVersion(value), value)
        }
    }

    func testHeartSamplesAreSortedDeduplicatedAndKeepMeasurementTime() throws {
        let points = try json(#"[{"heartRate":{"sampleTime":{"physicalTime":"2026-09-13T14:01:00.123Z"},"beatsPerMinute":"64"}},{"heartRate":{"sampleTime":{"physicalTime":"2026-09-13T14:00:00Z"},"beatsPerMinute":62}},{"heartRate":{"sampleTime":{"physicalTime":"2026-09-13T14:00:00Z"},"beatsPerMinute":62}},{"heartRate":{"beatsPerMinute":"70"}},{"heartRate":{"sampleTime":{"physicalTime":"2026-09-13T15:00:00Z"},"beatsPerMinute":"0"}}]"#).array
        let result = HealthParser.heart(points)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.bpm, 62)
        XCTAssertEqual(result.last?.bpm, 64)
        XCTAssertEqual(result.last?.time, HealthDate.parse("2026-09-13T14:01:00.123Z"))
    }

    func testSleepUsesFinalSummaryAndLocalWakeDateWithoutDoubleCountingAwakenings() throws {
        let point = try json(#"{"sleep":{"interval":{"startTime":"2026-09-12T16:00:00Z","endTime":"2026-09-13T00:00:00Z","endUtcOffset":"-25200s"},"metadata":{"mainSleep":true,"processed":true},"summary":{"minutesAsleep":"420","stagesSummary":[{"type":"DEEP","minutes":"80"},{"type":"AWAKE","minutes":"60"}]},"stages":[{"startTime":"2026-09-12T16:00:00Z","endTime":"2026-09-13T00:00:00Z","type":"LIGHT"}],"shortAwakenings":[{"startTime":"2026-09-12T17:00:00Z","endTime":"2026-09-12T17:02:00Z","type":"AWAKE"}]}}"#)
        let sleep = try XCTUnwrap(HealthParser.sleep([point]).first)
        XCTAssertEqual(sleep.day, "2026-09-12")
        XCTAssertEqual(sleep.minutesAsleep, 420)
        XCTAssertEqual(sleep.efficiency, 88)
        XCTAssertEqual(sleep.stageMinutes["DEEP"], 80)
        XCTAssertEqual(sleep.stages.count, 1)
    }

    func testIncompleteSleepAndMissingSummariesHaveNoInventedScore() throws {
        let sleep = try json(#"{"sleep":{"interval":{"startTime":"2026-09-12T22:00:00Z","endTime":"2026-09-13T06:00:00Z"},"metadata":{"processed":false},"summary":{"minutesAsleep":"420"}}}"#)
        XCTAssertNil(HealthParser.sleep([sleep]).first?.efficiency)
        let missing = try json(#"{"sleep":{"interval":{"startTime":"2026-09-12T22:00:00Z","endTime":"2026-09-13T06:00:00Z"}}}"#)
        XCTAssertNil(HealthParser.sleep([missing]).first?.minutesAsleep)
        XCTAssertNil(HealthParser.sleep([missing]).first?.efficiency)
    }

    func testSleepCivilDateUsesNestedDateObject() throws {
        let point = try json(#"{"sleep":{"interval":{"startTime":"2026-09-12T16:00:00Z","endTime":"2026-09-13T00:00:00Z","civilEndTime":{"date":{"year":2026,"month":9,"day":12},"time":{"hours":17}}},"summary":{"minutesAsleep":"420"}}}"#)
        XCTAssertEqual(HealthParser.sleep([point]).first?.day, "2026-09-12")
    }

    func testLatestMainSleepDoesNotGetReplacedByAfternoonNap() {
        let now = Date()
        var snapshot = HealthSnapshot()
        snapshot.sleep = [
            SleepSession(start: now.addingTimeInterval(-40000), end: now.addingTimeInterval(-12000), day: "2026-09-13", minutesAsleep: 450, stages: [], stageMinutes: [:], isMain: true),
            SleepSession(start: now.addingTimeInterval(-3600), end: now, day: "2026-09-13", minutesAsleep: 50, stages: [], stageMinutes: [:], isMain: false)
        ]
        XCTAssertEqual(snapshot.latestSleep?.minutesAsleep, 450)
    }

    func testRepresentativeSleepUsesMainSessionOrLongestFallbackForEachDay() {
        let now = Date()
        func sleep(day: String, hoursAgo: Double, minutes: Double, isMain: Bool) -> SleepSession {
            let end = now.addingTimeInterval(-hoursAgo * 3600)
            return SleepSession(start: end.addingTimeInterval(-minutes * 60), end: end, day: day,
                                minutesAsleep: minutes - 20, stages: [], stageMinutes: [:], isMain: isMain)
        }
        var snapshot = HealthSnapshot()
        snapshot.sleep = [
            sleep(day: "2026-09-12", hoursAgo: 30, minutes: 80, isMain: false),
            sleep(day: "2026-09-12", hoursAgo: 26, minutes: 420, isMain: false),
            sleep(day: "2026-09-13", hoursAgo: 12, minutes: 460, isMain: false),
            sleep(day: "2026-09-13", hoursAgo: 4, minutes: 50, isMain: true)
        ]

        XCTAssertEqual(snapshot.representativeSleepByDay.map(\.day), ["2026-09-12", "2026-09-13"])
        XCTAssertEqual(snapshot.representativeSleepByDay.map { Int($0.minutesInBed) }, [420, 50])
    }

    func testDailyMetricsUseDocumentedFieldsAndDateObjects() throws {
        let values = try json(#"[{"dailyHeartRateVariability":{"date":{"year":2026,"month":9,"day":13},"averageHeartRateVariabilityMilliseconds":52.4,"nonRemHeartRateBeatsPerMinute":"60"}},{"dailyHeartRateVariability":{"date":{"year":2026,"month":9,"day":12},"nonRemHeartRateBeatsPerMinute":"57"}}]"#).array
        let metrics = HealthParser.daily(values, key: "dailyHeartRateVariability", field: "averageHeartRateVariabilityMilliseconds")
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(metrics.first?.value, 52.4)
        XCTAssertEqual(metrics.first?.day, "2026-09-13")
    }

    func testFiltersRespectSleepEndTimeAndLocalMidnightAcrossDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let now = HealthDate.parse("2026-03-29T14:00:00Z")!
        let steps = HealthQuery.filter(type: "steps", now: now, calendar: calendar)
        XCTAssertTrue(steps.contains("steps.interval.start_time >= \"2026-03-29T00:00:00Z\""))
        let sleep = HealthQuery.filter(type: "sleep", now: now, calendar: calendar)
        XCTAssertTrue(sleep.contains("sleep.interval.end_time"))
        XCTAssertFalse(sleep.contains("start_time"))
        let daily = HealthQuery.filter(type: "daily-heart-rate-variability", now: now, calendar: calendar)
        XCTAssertEqual(daily, "daily_heart_rate_variability.date >= \"2026-03-23\" AND daily_heart_rate_variability.date < \"2026-03-30\"")
        let summer = HealthDate.parse("2026-09-13T12:00:00Z")!
        XCTAssertTrue(HealthQuery.filter(type: "steps", now: summer, calendar: calendar).contains("2026-09-12T23:00:00Z"))
    }

    func testRequestUsesReconciledWearableStreamAndSleepPageLimit() {
        let url = HealthQuery.url(type: "sleep", now: Date(), pageToken: "a+b/==")
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(parts.host, "health.googleapis.com")
        XCTAssertTrue(parts.path.hasSuffix("/sleep/dataPoints:reconcile"))
        XCTAssertEqual(parts.queryItems?.first(where: { $0.name == "pageSize" })?.value, "25")
        XCTAssertEqual(parts.queryItems?.first(where: { $0.name == "pageToken" })?.value, "a+b/==")
        XCTAssertTrue(url.absoluteString.contains("a%2Bb"))
        XCTAssertEqual(parts.queryItems?.first(where: { $0.name == "dataSourceFamily" })?.value, "users/me/dataSourceFamilies/google-wearables")
    }

    func testPKCEMatchesRFC7636TestVector() throws {
        XCTAssertEqual(OAuthPKCE.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let one = try OAuthPKCE.random(), two = try OAuthPKCE.random()
        XCTAssertNotEqual(one, two)
        XCTAssertEqual(one.count, 43)
        XCTAssertFalse(one.contains("="))
    }

    func testAuthorizationIsReadOnlyAndUsesOfflinePKCE() {
        let url = OAuthPKCE.authorizationURL(clientID: "example", redirect: "http://127.0.0.1:1234/oauth/callback", verifier: "verifier", state: "state")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first(where: { $0.name == "code_challenge_method" })?.value, "S256")
        XCTAssertEqual(query.first(where: { $0.name == "access_type" })?.value, "offline")
        XCTAssertTrue(OAuthPKCE.scopes.allSatisfy { $0.hasSuffix(".readonly") })
        XCTAssertFalse(query.contains(where: { $0.name == "client_secret" }))
    }

    func testCallbackRejectsWrongMissingAndDuplicateStateAndDeniedConsent() throws {
        func callback(_ query: String) -> URL { URL(string: "http://127.0.0.1:1234/oauth/callback?\(query)")! }
        XCTAssertEqual(try OAuthPKCE.callbackCode(url: callback("code=abc&state=good"), expectedState: "good"), "abc")
        for query in ["code=abc", "code=abc&state=bad", "code=abc&state=good&state=bad", "state=good", "code=a&code=b&state=good", "error=access_denied&state=good"] {
            XCTAssertThrowsError(try OAuthPKCE.callbackCode(url: callback(query), expectedState: "good"))
        }
    }

    func testTokenFormEscapesReservedCharacters() {
        let data = OAuthPKCE.form(["code": "a+b&c=d /?", "grant_type": "authorization_code"])
        XCTAssertEqual(String(data: data, encoding: .utf8), "code=a%2Bb%26c%3Dd%20%2F%3F&grant_type=authorization_code")
    }

    func testOAuthConfigurationRejectsWebClientAndNonGoogleClient() {
        let web = Data(#"{"web":{"client_id":"a.apps.googleusercontent.com","client_secret":"test","project_id":"demo","redirect_uris":["https://example.com"]}}"#.utf8)
        XCTAssertThrowsError(try OAuthConfiguration.read(web))
        let invalid = Data(#"{"installed":{"client_id":"untrusted.example","client_secret":"test","project_id":"demo","redirect_uris":["http://localhost"]}}"#.utf8)
        XCTAssertThrowsError(try OAuthConfiguration.read(invalid))
    }
}

private final class StubProtocol: URLProtocol {
    static var handler: (URLRequest) throws -> (Int, String) = { _ in (200, "{}") }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class HealthClientTests: XCTestCase {
    private func client() -> HealthClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return HealthClient(session: URLSession(configuration: config))
    }

    func testPaginationFollowsEveryPageIncludingEmptyIntermediatePage() async throws {
        StubProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let token = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "pageToken" })?.value
            switch token {
            case nil: return (200, #"{"dataPoints":[{"steps":{"count":"10"}}],"nextPageToken":"second"}"#)
            case "second": return (200, #"{"nextPageToken":"third"}"#)
            default: return (200, #"{"dataPoints":[{"steps":{"count":"15"}}]}"#)
            }
        }
        let points = try await client().points(type: "steps", token: "test-token", now: Date())
        XCTAssertEqual(HealthParser.steps(points), 25)
    }

    func testRepeatedTokenFailsInsteadOfReturningPartialTotal() async {
        StubProtocol.handler = { _ in (200, #"{"dataPoints":[{"steps":{"count":"10"}}],"nextPageToken":"same"}"#) }
        do { _ = try await client().points(type: "steps", token: "test", now: Date()); XCTFail("Expected pagination error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("incomplete")) }
    }

    func testSecondPageFailureDoesNotExposePartialStepCount() async {
        StubProtocol.handler = { request in
            if request.url!.absoluteString.contains("pageToken") { return (429, "{}") }
            return (200, #"{"dataPoints":[{"steps":{"count":"10"}}],"nextPageToken":"second"}"#)
        }
        do { _ = try await client().points(type: "steps", token: "test", now: Date()); XCTFail("Expected error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("request limit")) }
    }

    func testPartialConsentKeepsAllowedDataAndReportsDeniedMetric() async throws {
        StubProtocol.handler = { request in
            let path = request.url!.path
            if path.contains("/sleep/") { return (403, #"{"error":{"status":"PERMISSION_DENIED"}}"#) }
            if path.contains("/steps/") { return (200, #"{"dataPoints":[{"steps":{"count":"1234"}}]}"#) }
            if path.contains("pairedDevices") { return (200, #"{"pairedDevices":[{"name":"users/me/pairedDevices/air","deviceVersion":"Fitbit Air","batteryLevel":78,"deviceType":"TRACKER","lastSyncTime":"2026-09-13T12:30:00Z"}]}"#) }
            return (200, "{}")
        }
        let snapshot = try await client().snapshot(token: "test")
        XCTAssertEqual(snapshot.steps, 1234)
        XCTAssertTrue(snapshot.sleep.isEmpty)
        XCTAssertNotNil(snapshot.issues["sleep"])
        XCTAssertEqual(snapshot.issues.count, 1)
        XCTAssertEqual(snapshot.devices.first?.name, "Fitbit Air")
        XCTAssertEqual(snapshot.devices.first?.battery, 78)
    }

    func testUnlinkedAccountSaysHowToLinkInsteadOfTryAgainLater() async {
        let body = #"{"error":{"code":400,"message":"The account is not linked to Google Health.","status":"FAILED_PRECONDITION","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"ACCOUNT_NOT_LINKED"}]}}"#
        StubProtocol.handler = { _ in (400, body) }
        do { _ = try await client().points(type: "heart-rate", token: "test", now: Date()); XCTFail("Expected error") }
        catch {
            XCTAssertTrue(error.localizedDescription.contains("fitbit.google.com"), error.localizedDescription)
            XCTAssertFalse(error.localizedDescription.contains("Try again later"))
        }
    }

    func testOtherBadRequestsRepeatGooglesOwnExplanation() async {
        StubProtocol.handler = { _ in (400, #"{"error":{"code":400,"message":"Invalid filter field.","status":"INVALID_ARGUMENT"}}"#) }
        do { _ = try await client().points(type: "steps", token: "test", now: Date()); XCTFail("Expected error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Invalid filter field."), error.localizedDescription) }
    }

    func testFailedSourceKeepsTheLastKnownReadingRatherThanBlanking() async throws {
        StubProtocol.handler = { request in
            if request.url!.path.contains("/heart-rate/") { return (200, #"{"dataPoints":[{"heartRate":{"sampleTime":{"physicalTime":"2026-09-13T14:00:00Z"},"beatsPerMinute":62}}]}"#) }
            if request.url!.path.contains("/steps/") { return (200, #"{"dataPoints":[{"steps":{"count":"1234"}}]}"#) }
            return (200, "{}")
        }
        let good = try await client().snapshot(token: "test")
        StubProtocol.handler = { request in
            if request.url!.path.contains("/heart-rate/") { return (500, "{}") }
            return (200, "{}")
        }
        let degraded = try await client().snapshot(token: "test").preservingReadings(from: good)
        XCTAssertEqual(degraded.latestHeart?.bpm, 62)
        XCTAssertNotNil(degraded.issues["heart-rate"])
        XCTAssertNil(degraded.steps, "Steps succeeded with no data points and must not resurrect yesterday's total")
    }

    func testTemperatureIsDeviationOnlyWhenBaselineExists() async throws {
        StubProtocol.handler = { request in
            if request.url!.path.contains("daily-sleep-temperature") {
                return (200, #"{"dataPoints":[{"dailySleepTemperatureDerivations":{"date":{"year":2026,"month":9,"day":13},"nightlyTemperatureCelsius":33.2,"baselineTemperatureCelsius":33}},{"dailySleepTemperatureDerivations":{"date":{"year":2026,"month":9,"day":12},"nightlyTemperatureCelsius":34}}]}"#)
            }
            return (200, "{}")
        }
        let snapshot = try await client().snapshot(token: "test")
        XCTAssertEqual(snapshot.temperature.count, 1)
        XCTAssertEqual(try XCTUnwrap(snapshot.temperature.first?.value), 0.2, accuracy: 0.001)
    }
}
