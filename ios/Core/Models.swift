import Foundation

enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "男" : "女" }
}

struct Profile: Codable, Equatable {
    var sex: BiologicalSex = .male
    var age: Int = 30
    var heightCM: Double = 175
    var weightKG: Double = 70
    var dailyTarget: Double = 1800

    var isValid: Bool {
        (18...100).contains(age) && heightCM.isFinite && (100...230).contains(heightCM)
            && weightKG.isFinite && (25...300).contains(weightKG)
            && dailyTarget.isFinite && (800...6000).contains(dailyTarget)
    }

    var fingerprint: String { "\(sex.rawValue)|\(age)|\(heightCM)|\(weightKG)" }

    /// Adult resting energy expenditure, Mifflin–St Jeor; not a dietary target.
    var formulaKcal: Double {
        10 * weightKG + 6.25 * heightCM - 5 * Double(age) + (sex == .male ? 5 : -161)
    }
}

struct MetabolismResponse: Codable, Equatable {
    var estimatedKcal: Double
    var summary: String
    var assumptions: [String]
}

struct MetabolismAssessment: Codable, Equatable {
    var response: MetabolismResponse
    var profileFingerprint: String
    var createdAt: Date = Date()

    func matches(_ profile: Profile) -> Bool { profileFingerprint == profile.fingerprint }
    func canBlend(with profile: Profile) -> Bool {
        matches(profile) && response.estimatedKcal.isFinite
            && (600...5000).contains(response.estimatedKcal)
            && abs(response.estimatedKcal - profile.formulaKcal) / profile.formulaKcal <= 0.20
    }
}

enum Metabolism {
    /// Explicit product heuristic; this weighting has not been clinically validated.
    static func combined(profile: Profile, assessment: MetabolismAssessment?) -> Double {
        guard let assessment, assessment.canBlend(with: profile) else { return profile.formulaKcal }
        return profile.formulaKcal * 0.8 + assessment.response.estimatedKcal * 0.2
    }
}

enum MealKind: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
    var label: String {
        switch self {
        case .breakfast: return "早餐"
        case .lunch: return "午餐"
        case .dinner: return "晚餐"
        case .snack: return "加餐"
        }
    }
    var symbol: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snack: return "cup.and.saucer"
        }
    }
    static func suggested(at date: Date = Date(), calendar: Calendar = .current) -> MealKind {
        switch calendar.component(.hour, from: date) {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}

struct FoodItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var grams: Double?
    var kcal: Double

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80
            && kcal.isFinite && (0...10000).contains(kcal)
            && (grams == nil || (grams!.isFinite && grams! > 0 && grams! <= 10000))
    }
    func scaled(by fraction: Double) -> FoodItem {
        FoodItem(id: id, name: name, grams: grams.map { $0 * fraction }, kcal: kcal * fraction)
    }
}

struct RecognizedFood: Codable, Equatable {
    var name: String
    var estimatedGrams: Double
    var estimatedKcal: Double
    var foodItem: FoodItem { FoodItem(name: name, grams: estimatedGrams, kcal: estimatedKcal) }
}

struct MealAnalysis: Codable, Equatable {
    var items: [RecognizedFood]
    var summary: String
    var assumptions: [String]
    var questions: [String]
    var clarifications: [MealClarification]?
    var portionBasis: String?
    var confirmationApplied: Bool?

    var pendingQuestions: [MealClarification] {
        var seen = Set<String>()
        let fallback = questions.map { MealClarification(question: $0, options: []) }
        return ((clarifications ?? []) + fallback).filter { seen.insert($0.question).inserted }
            .prefix(8).map { $0 }
    }
}

struct MealClarification: Codable, Equatable {
    let question: String
    let options: [String]
}

struct MealClarificationAnswer: Encodable {
    let question: String
    let answer: String?
}

struct Meal: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var consumedAt: Date
    var kind: MealKind
    var items: [FoodItem]
    var source: String
    var summary: String = ""
    var assumptions: [String] = []
    var photoFilename: String?
    var createdAt: Date = Date()
    var totalKcal: Double { items.reduce(0) { $0 + $1.kcal } }
    var isValid: Bool { !items.isEmpty && items.count <= 30 && items.allSatisfy(\.isValid) }
}

struct AppSnapshot: Codable, Equatable {
    var schemaVersion: Int = 1
    var profile: Profile?
    var metabolism: MetabolismAssessment?
    var meals: [Meal] = []
    var aiConsent: Bool = false
    var activityDays: [ActivityDay] = []

    func meals(on day: Date, calendar: Calendar = .current) -> [Meal] {
        meals.filter { calendar.isDate($0.consumedAt, inSameDayAs: day) }
            .sorted { $0.consumedAt < $1.consumedAt }
    }
}

struct ActivityDay: Codable, Equatable, Identifiable {
    var id: String
    var day: String
    var timeZone: String
    var activeKcal: Double
    var updatedAt: Date

    static func key(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

extension AppSnapshot {
    enum CodingKeys: String, CodingKey { case schemaVersion, profile, metabolism, meals, aiConsent, activityDays }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        profile = try values.decodeIfPresent(Profile.self, forKey: .profile)
        metabolism = try values.decodeIfPresent(MetabolismAssessment.self, forKey: .metabolism)
        meals = try values.decode([Meal].self, forKey: .meals)
        aiConsent = try values.decodeIfPresent(Bool.self, forKey: .aiConsent) ?? false
        activityDays = try values.decodeIfPresent([ActivityDay].self, forKey: .activityDays) ?? []
    }
}

enum NumberText {
    static func parse(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }
}
