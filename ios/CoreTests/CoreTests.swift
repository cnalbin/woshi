import XCTest
@testable import QingJiCore

final class CoreTests: XCTestCase {
    func testIndependentOfflineEditsMergeAndDeletionPropagates() throws {
        let first = Meal(consumedAt: Date(), kind: .lunch, items: [FoodItem(name: "A", kcal: 100)], source: "manual")
        let second = Meal(consumedAt: Date(), kind: .dinner, items: [FoodItem(name: "B", kcal: 200)], source: "manual")
        var base = AppSnapshot()
        base.meals = [first]
        var local = base
        local.meals = []
        var remote = base
        remote.meals.append(second)
        let merged = try SnapshotMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(merged.meals.map(\.id), [second.id])
        local = base
        local.meals[0].items[0].kcal = 150
        remote = base
        remote.meals[0].items[0].kcal = 175
        XCTAssertThrowsError(try SnapshotMerge.merge(base: base, local: local, remote: remote))
    }
    func testLegacySnapshotRestoresWithoutActivityField() throws {
        let legacy = Data(#"{"schemaVersion":1,"meals":[],"aiConsent":true}"#.utf8)
        let snapshot = try JSONDecoder().decode(AppSnapshot.self, from: legacy)
        XCTAssertTrue(snapshot.aiConsent)
        XCTAssertTrue(snapshot.activityDays.isEmpty)
    }
    func testAnalysisEventsWithoutEmptySeparatorsAsDeliveredByFoundation() throws {
        var parser = AnalysisEventParser()
        let lines = ["event: progress", "data: {\"stage\":\"analyzing\",\"message\":\"正在分析\"}",
            ": keepalive", "event: result", "data: {\"estimatedKcal\":1700,\"summary\":\"中文结果\",\"assumptions\":[]}"]
        let frames = try lines.compactMap { try parser.consume($0) }
        XCTAssertEqual(frames.map(\.name), ["progress", "result"])
        let result = try JSONDecoder().decode(MetabolismResponse.self, from: frames[1].data)
        XCTAssertEqual(result.estimatedKcal, 1700)
        XCTAssertEqual(result.summary, "中文结果")
    }
    func testAnalysisEventsWithCRLFAndBlankLinesAndOversizedPayload() throws {
        var parser = AnalysisEventParser()
        XCTAssertNil(try parser.consume("event: error\r"))
        let frame = try XCTUnwrap(parser.consume("data: {\"message\":\"失败\"}\r"))
        XCTAssertEqual(frame.name, "error")
        XCTAssertNil(try parser.consume(""))
        XCTAssertNil(try parser.consume(": keepalive"))
        XCTAssertNil(try parser.consume("event: result"))
        XCTAssertThrowsError(try parser.consume("data: " + String(repeating: "x", count: 100001)))
    }
    func testFormulaAndIndependentDietTarget() {
        var profile = Profile()
        XCTAssertEqual(profile.formulaKcal, 1648.75, accuracy: 0.001)
        profile.sex = .female
        XCTAssertEqual(profile.formulaKcal, 1482.75, accuracy: 0.001)
        profile.dailyTarget = 2300
        XCTAssertEqual(profile.formulaKcal, 1482.75, accuracy: 0.001)
    }
    func testFusionAndStaleOrAbnormalAIResults() {
        let profile = Profile()
        var result = MetabolismAssessment(response: .init(estimatedKcal: 1700, summary: "参考估算", assumptions: []), profileFingerprint: profile.fingerprint)
        XCTAssertEqual(Metabolism.combined(profile: profile, assessment: result), 1659, accuracy: 0.001)
        result.response.estimatedKcal = 3000
        XCTAssertEqual(Metabolism.combined(profile: profile, assessment: result), profile.formulaKcal)
        result.response.estimatedKcal = 1700
        result.profileFingerprint = "old"
        XCTAssertEqual(Metabolism.combined(profile: profile, assessment: result), profile.formulaKcal)
    }
    func testFractionDoesNotCompoundAndPreservesIdentity() {
        let food = FoodItem(name: "米饭", grams: 150, kcal: 174)
        let half = food.scaled(by: 0.5)
        XCTAssertEqual(half.kcal, 87)
        XCTAssertEqual(half.grams, 75)
        XCTAssertEqual(half.id, food.id)
        XCTAssertEqual(food.scaled(by: 1).kcal, 174)
    }
    func testValidationRejectsNonFiniteAndInvalidInputs() {
        var profile = Profile()
        profile.age = 17
        XCTAssertFalse(profile.isValid)
        XCTAssertFalse(FoodItem(name: "", kcal: 100).isValid)
        XCTAssertFalse(FoodItem(name: "饭", grams: -1, kcal: 100).isValid)
        XCTAssertFalse(FoodItem(name: "饭", kcal: .infinity).isValid)
        XCTAssertTrue(FoodItem(name: "快速记录", kcal: 250).isValid)
        XCTAssertEqual(NumberText.parse(" 12,5 "), 12.5)
    }
    func testDailyRecordsUseCalendarDaysAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let iso = ISO8601DateFormatter()
        let morning = try XCTUnwrap(iso.date(from: "2026-03-08T06:30:00Z"))
        let evening = try XCTUnwrap(iso.date(from: "2026-03-09T03:30:00Z"))
        let next = try XCTUnwrap(iso.date(from: "2026-03-09T05:00:00Z"))
        let snapshot = AppSnapshot(meals: [morning, evening, next].map {
            Meal(consumedAt: $0, kind: .snack, items: [.init(name: "食物", kcal: 100)], source: "manual")
        })
        XCTAssertEqual(snapshot.meals(on: morning, calendar: calendar).count, 2)
        let encoded = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(AppSnapshot.self, from: encoded).meals.count, 3)
    }
}
