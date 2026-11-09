import Foundation

enum TrendPeriod: Int, CaseIterable, Identifiable {
    case week, month, year
    var id: Int { rawValue }
    var label: String { ["周", "月", "年"][rawValue] }
    var component: Calendar.Component { self == .week ? .weekOfYear : self == .month ? .month : .year }
}

struct TrendBucket: Identifiable {
    let date: Date
    let slot: Int
    let label: String
    let intake: Double?
    let activity: Double?
    let total: Double?
    let meals: [Meal]
    var id: Int { slot }
}

struct TrendReport {
    let period: TrendPeriod
    let interval: DateInterval
    let title: String
    let buckets: [TrendBucket]
    let intakeAverage: Double?
    let activityAverage: Double?
    let totalAverage: Double?
    let recordedDays: Int
    let elapsedDays: Int
    var hasData: Bool { buckets.contains { $0.intake != nil || $0.activity != nil } }

    /// One pass over records, followed by at most 366 daily buckets. Call off the UI actor.
    static func build(snapshot: AppSnapshot, period: TrendPeriod, anchor: Date,
                      now: Date = Date(), calendar input: Calendar = .current) throws -> TrendReport {
        var calendar = input
        calendar.firstWeekday = 2
        let interval = calendar.dateInterval(of: period.component, for: anchor)!
        var grouped: [Date: [Meal]] = [:]
        for meal in snapshot.meals where meal.consumedAt >= interval.start && meal.consumedAt < interval.end && meal.consumedAt <= now {
            try Task.checkCancellation()
            grouped[calendar.startOfDay(for: meal.consumedAt), default: []].append(meal)
        }
        var activity: [String: ActivityDay] = [:]
        for day in snapshot.activityDays where day.timeZone == calendar.timeZone.identifier {
            if activity[day.day].map({ $0.updatedAt > day.updatedAt }) != true { activity[day.day] = day }
        }
        let resting = snapshot.profile.map { Metabolism.combined(profile: $0, assessment: snapshot.metabolism) }
        let count = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        var days: [TrendBucket] = []
        for offset in 0..<count {
            try Task.checkCancellation()
            let date = calendar.date(byAdding: .day, value: offset, to: interval.start)!
            guard date <= now else { break }
            let meals = (grouped[date] ?? []).sorted { $0.consumedAt < $1.consumedAt }
            let energy = activity[ActivityDay.key(for: date, timeZone: calendar.timeZone)]?.activeKcal
            days.append(TrendBucket(date: date, slot: offset, label: String(calendar.component(.day, from: date)),
                intake: meals.isEmpty ? nil : meals.reduce(0) { $0 + $1.totalKcal }, activity: energy,
                total: energy.flatMap { active in resting.map { active + $0 } }, meals: meals))
        }
        let buckets: [TrendBucket]
        if period == .year {
            let months = Dictionary(grouping: days) { calendar.component(.month, from: $0.date) }
            buckets = (1...12).map { month in
                let values = months[month] ?? []
                let date = calendar.date(byAdding: .month, value: month - 1, to: interval.start)!
                return TrendBucket(date: date, slot: month - 1, label: "\(month)月", intake: mean(values.compactMap(\.intake)),
                    activity: mean(values.compactMap(\.activity)), total: mean(values.compactMap(\.total)), meals: [])
            }
        } else {
            // Keep future days as empty slots so the chart never shifts its domain during the day.
            buckets = (0..<count).map { offset in
                if offset < days.count { return days[offset] }
                let date = calendar.date(byAdding: .day, value: offset, to: interval.start)!
                return TrendBucket(date: date, slot: offset, label: String(calendar.component(.day, from: date)),
                    intake: nil, activity: nil, total: nil, meals: [])
            }
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = period == .year ? "yyyy年" : period == .month ? "yyyy年M月" : "M月d日"
        let title: String
        if period == .week {
            let last = calendar.date(byAdding: .day, value: -1, to: interval.end)!
            title = formatter.string(from: interval.start) + " — " + formatter.string(from: last)
        } else { title = formatter.string(from: interval.start) }
        return TrendReport(period: period, interval: interval, title: title, buckets: buckets,
            intakeAverage: mean(days.compactMap(\.intake)), activityAverage: mean(days.compactMap(\.activity)),
            totalAverage: mean(days.compactMap(\.total)), recordedDays: days.filter { $0.intake != nil }.count,
            elapsedDays: days.count)
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
