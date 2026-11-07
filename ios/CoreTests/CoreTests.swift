import XCTest
@testable import QingJiCore

final class CoreTests: XCTestCase {
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
