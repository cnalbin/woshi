import XCTest
@testable import QingJiCore

final class TrendReportTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "UTC")!
        return result
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testSeparateAveragesMissingZeroAndLeapYear() throws {
        let start = date("2024-01-01T12:00:00Z")
        let second = date("2024-01-02T12:00:00Z")
        var snapshot = AppSnapshot(profile: Profile())
        snapshot.meals = [Meal(consumedAt: start, kind: .lunch, items: [.init(name: "A", kcal: 250)], source: "manual"),
                          Meal(consumedAt: second, kind: .lunch, items: [.init(name: "B", kcal: 0)], source: "manual")]
        snapshot.activityDays = [(start, 50.0), (second, 0.0)].map { date, value in
            let day = ActivityDay.key(for: date, timeZone: calendar.timeZone)
            return ActivityDay(id: day, day: day, timeZone: "GMT", activeKcal: value, updatedAt: start)
        }
        // Foundation canonicalizes TimeZone(identifier: "UTC") as GMT.
        snapshot.activityDays = snapshot.activityDays.map { var value = $0; value.timeZone = calendar.timeZone.identifier; return value }
        let report = try TrendReport.build(snapshot: snapshot, period: .year, anchor: start,
            now: date("2024-12-31T23:59:59Z"), calendar: calendar)
        XCTAssertEqual(report.elapsedDays, 366)
        XCTAssertEqual(report.recordedDays, 2)
        XCTAssertEqual(report.intakeAverage, 125)
        XCTAssertEqual(report.activityAverage, 25)
        XCTAssertEqual(try XCTUnwrap(report.totalAverage), Profile().formulaKcal + 25, accuracy: 0.001)
        XCTAssertEqual(report.buckets.count, 12)
        XCTAssertEqual(report.buckets[0].intake, 125)
        XCTAssertNil(report.buckets[1].intake)
        let month = try TrendReport.build(snapshot: snapshot, period: .month, anchor: start, now: second, calendar: calendar)
        XCTAssertEqual(month.buckets.count, 31)
        XCTAssertEqual(month.buckets[1].intake, 0)
        XCTAssertNil(month.buckets[2].intake)
        XCTAssertEqual(month.title, "2024年1月")
    }

    func testNoProfileDoesNotInventTotalAndDSTUsesLocalDays() throws {
        var calendar = self.calendar
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let first = date("2026-03-08T06:30:00Z")
        let last = date("2026-03-09T03:30:00Z")
        var snapshot = AppSnapshot()
        snapshot.meals = [first, last].map { Meal(consumedAt: $0, kind: .snack, items: [.init(name: "A", kcal: 100)], source: "manual") }
        let report = try TrendReport.build(snapshot: snapshot, period: .week, anchor: first, now: last, calendar: calendar)
        XCTAssertEqual(report.recordedDays, 1)
        XCTAssertEqual(report.intakeAverage, 200)
        XCTAssertNil(report.totalAverage)
        XCTAssertEqual(report.buckets.count, 7)
        XCTAssertEqual(ActivityDay.key(for: last, timeZone: calendar.timeZone), "2026-03-08")
    }

    func testTenThousandRecordsYearAggregationPerformance() throws {
        let now = date("2026-11-09T12:00:00Z")
        let calendar = self.calendar
        var snapshot = AppSnapshot(profile: Profile())
        snapshot.meals = (0..<10000).map { index in
            Meal(consumedAt: calendar.date(byAdding: .day, value: -(index % 730), to: now)!, kind: .lunch,
                 items: [.init(name: "历史记录", kcal: 100)], source: "manual")
        }
        measure {
            let result = try! TrendReport.build(snapshot: snapshot, period: .year, anchor: now, now: now, calendar: calendar)
            XCTAssertEqual(result.buckets.count, 12)
            XCTAssertEqual(result.recordedDays, 313)
        }
    }
}
