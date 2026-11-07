import Foundation
import HealthKit

@MainActor
final class HealthService: ObservableObject {
    @Published var activeKcal: Double?
    @Published var lastUpdated: Date?
    @Published var message = "连接苹果健康，查看活动消耗"
    @Published var refreshing = false
    @Published private(set) var hasRequested = UserDefaults.standard.bool(forKey: "healthRequested")
    private let store = HKHealthStore()
    private var observer: HKObserverQuery?
    private var selectedDay = Date()
    private var refreshGeneration = UUID()

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    func connect() async {
        guard available else { message = "当前设备不支持苹果健康"; return }
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: [type])
            hasRequested = true
            UserDefaults.standard.set(true, forKey: "healthRequested")
            observe()
            await refresh(for: selectedDay)
        } catch { message = "连接未完成，请在系统健康权限中检查" }
    }

    func start() {
        if hasRequested && available { observe() }
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

    func refresh(for day: Date) async {
        selectedDay = day
        guard hasRequested, available,
              let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            activeKcal = nil
            return
        }
        let generation = UUID()
        refreshGeneration = generation
        refreshing = true
        activeKcal = nil
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
        }
    }
}
