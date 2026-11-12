import Foundation
import HealthKit

enum HealthMetric: String, CaseIterable, Identifiable {
    case activity, steps, weight, sleep, heartRate
    var id: String { rawValue }
    var label: String {
        switch self {
        case .activity: "活动能量"
        case .steps: "步数"
        case .weight: "体重"
        case .sleep: "睡眠"
        case .heartRate: "心率"
        }
    }
    var symbol: String {
        switch self {
        case .activity: "flame"
        case .steps: "figure.walk"
        case .weight: "scalemass"
        case .sleep: "bed.double"
        case .heartRate: "heart"
        }
    }
    var type: HKObjectType? {
        switch self {
        case .activity: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        case .steps: HKQuantityType.quantityType(forIdentifier: .stepCount)
        case .weight: HKQuantityType.quantityType(forIdentifier: .bodyMass)
        case .sleep: HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)
        case .heartRate: HKQuantityType.quantityType(forIdentifier: .heartRate)
        }
    }
}

@MainActor
final class HealthService: ObservableObject {
    @Published var activeKcal: Double?
    @Published var lastUpdated: Date?
    @Published var message = "连接苹果健康，查看活动消耗"
    @Published var refreshing = false
    @Published private(set) var observation: ActivityDay?
    @Published private(set) var hasRequested: Bool
    @Published private(set) var selected: Set<String>
    private let preference: String
    private let selectionsKey: String
    private let store = HKHealthStore()
    private var observer: HKObserverQuery?
    private var selectedDay = Date()
    private var refreshGeneration = UUID()

    init(workspaceID: String) {
        preference = workspaceID.isEmpty ? "healthRequested" : "healthRequested.\(workspaceID)"
        selectionsKey = "healthMetrics.\(workspaceID)"
        hasRequested = UserDefaults.standard.bool(forKey: preference)
        selected = Set(UserDefaults.standard.stringArray(forKey: selectionsKey) ?? ["activity"])
    }

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    func synchronize(_ selection: Set<String>, into appStore: AppStore) async {
        guard available else { message = "当前设备不支持苹果健康"; return }
        let types = Set(HealthMetric.allCases.filter { selection.contains($0.rawValue) }.compactMap(\.type))
        do {
            if !types.isEmpty { try await store.requestAuthorization(toShare: [], read: types) }
            selected = selection
            UserDefaults.standard.set(Array(selection).sorted(), forKey: selectionsKey)
            hasRequested = true
            UserDefaults.standard.set(true, forKey: preference)
            if !selection.contains("activity") {
                if let observer { store.stop(observer) }
                observer = nil
                refreshGeneration = UUID()
                refreshing = false
                activeKcal = nil
            }
            if selection.contains("activity") {
                observe()
                await refresh(for: selectedDay)
                appStore.saveActivities(await history())
            }
            let values = await metricHistory(selection)
            if !Task.isCancelled { appStore.saveHealthMetrics(values) }
            lastUpdated = Date()
            message = "同步完成"
        } catch { message = "同步未完成，请检查苹果健康设置" }
    }

    private func metricHistory(_ selection: Set<String>) async -> [HealthMetricRecord] {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -730, to: calendar.startOfDay(for: Date())) else { return [] }
        var result: [HealthMetricRecord] = []
        for metric in HealthMetric.allCases where metric != .activity && selection.contains(metric.rawValue) {
            if metric == .steps || metric == .heartRate {
                result.append(contentsOf: await dailyStatistics(metric, start: start, calendar: calendar))
                continue
            }
            guard let type = metric.type as? HKSampleType else { continue }
            let samples: [HKSample] = await withCheckedContinuation { continuation in
                let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
                let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                          sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]) { _, samples, _ in
                    continuation.resume(returning: samples ?? [])
                }
                store.execute(query)
            }
            var days: [String: [Double]] = [:]
            var sleepIntervals: [String: [(Date, Date)]] = [:]
            for sample in samples {
                let key = ActivityDay.key(for: sample.endDate, timeZone: calendar.timeZone)
                if let quantity = sample as? HKQuantitySample {
                    let unit: HKUnit = metric == .weight ? .gramUnit(with: .kilo) : metric == .heartRate ? HKUnit.count().unitDivided(by: .minute()) : .count()
                    days[key, default: []].append(quantity.quantity.doubleValue(for: unit))
                } else if let category = sample as? HKCategorySample, metric == .sleep,
                          category.value != HKCategoryValueSleepAnalysis.inBed.rawValue,
                          category.value != HKCategoryValueSleepAnalysis.awake.rawValue {
                    sleepIntervals[key, default: []].append((category.startDate, category.endDate))
                }
            }
            for (day, intervals) in sleepIntervals {
                var end = Date.distantPast
                var duration = 0.0
                for interval in intervals.sorted(by: { $0.0 < $1.0 }) {
                    duration += max(0, interval.1.timeIntervalSince(max(end, interval.0)))
                    end = max(end, interval.1)
                }
                days[day] = [duration / 3600]
            }
            for (day, values) in days where !values.isEmpty {
                let value = metric == .weight ? values.last! : metric == .heartRate ? values.reduce(0, +) / Double(values.count) : values.reduce(0, +)
                result.append(HealthMetricRecord(id: "\(metric.rawValue)|\(day)|\(calendar.timeZone.identifier)", day: day,
                                                 timeZone: calendar.timeZone.identifier, metric: metric.rawValue,
                                                 value: value, updatedAt: Date()))
            }
        }
        return result
    }

    private func dailyStatistics(_ metric: HealthMetric, start: Date, calendar: Calendar) async -> [HealthMetricRecord] {
        guard let type = metric.type as? HKQuantityType else { return [] }
        let unit: HKUnit = metric == .steps ? .count() : HKUnit.count().unitDivided(by: .minute())
        let options: HKStatisticsOptions = metric == .steps ? .cumulativeSum : .discreteAverage
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                    options: options, anchorDate: start, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, _ in
                var records: [HealthMetricRecord] = []
                collection?.enumerateStatistics(from: start, to: Date()) { statistics, _ in
                    let quantity = metric == .steps ? statistics.sumQuantity() : statistics.averageQuantity()
                    guard let value = quantity?.doubleValue(for: unit) else { return }
                    let day = ActivityDay.key(for: statistics.startDate, timeZone: calendar.timeZone)
                    records.append(HealthMetricRecord(id: "\(metric.rawValue)|\(day)|\(calendar.timeZone.identifier)",
                        day: day, timeZone: calendar.timeZone.identifier, metric: metric.rawValue, value: value, updatedAt: Date()))
                }
                continuation.resume(returning: records)
            }
            store.execute(query)
        }
    }

    func connect() async {
        guard available else { message = "当前设备不支持苹果健康"; return }
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: [type])
            selected.insert("activity")
            UserDefaults.standard.set(Array(selected).sorted(), forKey: selectionsKey)
            hasRequested = true
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(true, forKey: preference)
            observe()
            await refresh(for: selectedDay)
        } catch { message = "连接未完成，请在系统健康权限中检查" }
    }

    func start() {
        if hasRequested && available && selected.contains("activity") { observe() }
    }

    func stop() {
        if let observer { store.stop(observer) }
        observer = nil
        refreshGeneration = UUID()
        refreshing = false
    }

    private func observe() {
        guard observer == nil,
              let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
            Task { @MainActor in
                if let self { await self.refresh(for: self.selectedDay) }
                completion()
            }
        }
        observer = query
        store.execute(query)
        store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
    }

    func history() async -> [ActivityDay] {
        guard hasRequested, available, selected.contains("activity"),
              let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let start = Calendar.current.date(byAdding: .day, value: -730, to: Date()) else { return [] }
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: start)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: anchor, end: Date()),
                options: .cumulativeSum, anchorDate: anchor, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, result, _ in
                var values: [ActivityDay] = []
                result?.enumerateStatistics(from: anchor, to: Date()) { statistics, _ in
                    if let energy = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                        let day = ActivityDay.key(for: statistics.startDate, timeZone: calendar.timeZone)
                        values.append(ActivityDay(id: "\(day)|\(calendar.timeZone.identifier)", day: day,
                            timeZone: calendar.timeZone.identifier, activeKcal: energy, updatedAt: Date()))
                    }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    func refresh(for day: Date) async {
        let sameDay = Calendar.current.isDate(selectedDay, inSameDayAs: day)
        if refreshing && sameDay { return }
        selectedDay = day
        guard hasRequested, available, selected.contains("activity"),
              let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            activeKcal = nil
            return
        }
        let generation = UUID()
        refreshGeneration = generation
        refreshing = true
        if !sameDay { activeKcal = nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { refreshing = false; return }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: min(end, Date()), options: [])
        let value: (Double?, Bool) = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                continuation.resume(returning: (statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()), error != nil))
            }
            store.execute(query)
        }
        guard refreshGeneration == generation else { return }
        refreshing = false
        activeKcal = value.0
        if value.1 { message = "暂时无法读取，请解锁设备后重试" }
        else if value.0 == nil { message = "暂无可读取数据，请检查健康权限或数据来源" }
        else {
            message = "来自苹果健康 · 包含日常活动与训练"
            lastUpdated = Date()
            if let energy = value.0 {
                let zone = calendar.timeZone
                let key = ActivityDay.key(for: start, timeZone: zone)
                observation = ActivityDay(id: "\(key)|\(zone.identifier)", day: key,
                                          timeZone: zone.identifier, activeKcal: energy, updatedAt: Date())
            }
        }
    }
}
