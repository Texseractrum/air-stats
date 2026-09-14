import XCTest
@testable import HealthCore

final class ChartSeriesTests: XCTestCase {
    func testFiveMinuteMeansAreSortedAndSplitAtMissingBuckets() {
        let samples = [(660.0, 80.0), (30, 60), (90, 80), (310, 75), (1200, 90)]
            .map { HeartSample(time: Date(timeIntervalSince1970: $0.0), bpm: $0.1) }
        let points = ChartSeries.heart(samples)
        XCTAssertEqual(points.map(\.time.timeIntervalSince1970), [0, 300, 600, 1200])
        XCTAssertEqual(points.map(\.value), [70, 75, 80, 90])
        XCTAssertEqual(points.map(\.series), [0, 0, 0, 1])
        XCTAssertEqual(ChartSeries.isolatedSeries(points), [1])
    }

    func testEmptyAndInvalidHeartReadingsDoNotProduceZeroData() {
        XCTAssertTrue(ChartSeries.heart([]).isEmpty)
        let readings = [Double.nan, .infinity, 0, -1].map { HeartSample(time: Date(), bpm: $0) }
        XCTAssertTrue(ChartSeries.heart(readings).isEmpty)
        XCTAssertEqual(ChartSeries.isolatedSeries(ChartSeries.heart([HeartSample(time: Date(), bpm: 64)])), [0])
    }

    func testDailyLinesLeaveMissingDatesUnconnected() {
        let points = ChartSeries.daily([
            DailyMetric(day: "2026-09-14", value: 55), DailyMetric(day: "2026-09-10", value: 45),
            DailyMetric(day: "2026-09-11", value: 49), DailyMetric(day: "2026-09-13", value: 51)
        ])
        XCTAssertEqual(points.map(\.value), [45, 49, 51, 55])
        XCTAssertEqual(points.map(\.series), [0, 0, 1, 1])
    }

    func testConsecutiveCivilDaysStayConnectedAcrossBothDSTChanges() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        for days in [["2026-03-28", "2026-03-29", "2026-03-30"], ["2026-10-24", "2026-10-25", "2026-10-26"]] {
            let points = ChartSeries.daily(days.map { DailyMetric(day: $0, value: 50) }, calendar: calendar)
            XCTAssertEqual(points.map(\.series), [0, 0, 0])
            XCTAssertEqual(points.map { HealthDate.day($0.time, calendar: calendar) }, days)
        }
    }

    func testMalformedDaysAndNonfiniteValuesAreExcluded() {
        XCTAssertNil(ChartSeries.civilDate("2026-02-30"))
        XCTAssertNil(ChartSeries.civilDate("unknown"))
        XCTAssertTrue(ChartSeries.daily([DailyMetric(day: "2026-09-14", value: .nan)]).isEmpty)
        let points = ChartSeries.daily([DailyMetric(day: "2026-09-14", value: 50), DailyMetric(day: "2026-09-14", value: 52)])
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.value, 52)
    }

    func testFlatReadingsHaveANondegenerateHonestScale() {
        let range = ChartSeries.domain([57, 57, 57], minimumSpan: 20, floor: 0)
        XCTAssertEqual(range.upperBound - range.lowerBound, 20)
        XCTAssertTrue(range.contains(57))
        XCTAssertEqual(ChartSeries.domain([], minimumSpan: 20, floor: 0), 0...20)
    }

    func testPercentageAndTemperatureDomainsContainTheirValues() {
        XCTAssertEqual(ChartSeries.domain([97.4], minimumSpan: 10, floor: 0, ceiling: 100), 90...100)
        let temperature = ChartSeries.domain([-0.3, 0, 0.2], minimumSpan: 1)
        XCTAssertTrue(temperature.contains(-0.3))
        XCTAssertTrue(temperature.contains(0))
        XCTAssertTrue(temperature.contains(0.2))
        XCTAssertGreaterThanOrEqual(temperature.upperBound - temperature.lowerBound, 1)
    }
}
