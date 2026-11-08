import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var period = 0
    @State private var anchor = Date()
    @State private var activityOnly = false
    @State private var selected: Date?
    private var calendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    private var component: Calendar.Component { period == 0 ? .weekOfYear : period == 1 ? .month : .year }
    private var interval: DateInterval { calendar.dateInterval(of: component, for: anchor)! }
    private var periodTitle: String {
        if period == 2 { return anchor.formatted(.dateTime.year()) }
        if period == 1 { return anchor.formatted(.dateTime.year().month()) }
        let last = calendar.date(byAdding: .day, value: -1, to: interval.end)!
        return interval.start.formatted(.dateTime.month().day()) + " — " + last.formatted(.dateTime.month().day())
    }
    private struct Day: Identifiable {
        var date: Date
        var intake: Double?
        var activity: Double?
        var total: Double?
        var id: Date { date }
    }
    private var days: [Day] {
        let count = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: interval.start), date <= Date() else { return nil }
            let meals = store.snapshot.meals(on: date, calendar: calendar)
            let energy = store.snapshot.activityDays.first {
                $0.day == ActivityDay.key(for: date) && $0.timeZone == calendar.timeZone.identifier
            }?.activeKcal
            let resting = store.snapshot.profile.map { Metabolism.combined(profile: $0, assessment: store.snapshot.metabolism) }
            return Day(date: date, intake: meals.isEmpty ? nil : meals.reduce(0) { $0 + $1.totalKcal },
                       activity: energy, total: energy.flatMap { active in resting.map { $0 + active } })
        }
    }
    private func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
    private func text(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))" } ?? "—" }
    private var buckets: [Day] {
        guard period == 2 else { return days }
        return (1...12).compactMap { month in
            let values = days.filter { calendar.component(.month, from: $0.date) == month }
            guard let date = values.first?.date else { return nil }
            return Day(date: date, intake: mean(values.compactMap(\.intake)),
                       activity: mean(values.compactMap(\.activity)), total: mean(values.compactMap(\.total)))
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("范围", selection: $period) {
                        Text("周").tag(0); Text("月").tag(1); Text("年").tag(2)
                    }.pickerStyle(.segmented)
                    HStack {
                        Button { move(-1) } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        Text(periodTitle)
                        Spacer()
                        Button { move(1) } label: { Image(systemName: "chevron.right") }
                            .disabled(interval.end > Date())
                    }
                    HStack {
                        metric("日均摄入", text(mean(days.compactMap(\.intake))))
                        metric("日均消耗", text(mean(days.compactMap { activityOnly ? $0.activity : $0.total })))
                        metric("记录天数", "\(days.filter { $0.intake != nil }.count)/\(days.count)")
                    }
                    Card {
                        Text(period == 2 ? "各月日均摄入与消耗" : "每日摄入与消耗").font(.headline)
                        Chart(buckets) { day in
                            if let intake = day.intake {
                                BarMark(x: .value("日期", day.date, unit: period == 2 ? .month : .day),
                                        y: .value("kcal", intake))
                                    .position(by: .value("项目", "摄入")).foregroundStyle(by: .value("项目", "摄入"))
                            }
                            if let energy = activityOnly ? day.activity : day.total {
                                BarMark(x: .value("日期", day.date, unit: period == 2 ? .month : .day),
                                        y: .value("kcal", energy))
                                    .position(by: .value("项目", "消耗")).foregroundStyle(by: .value("项目", "消耗"))
                            }
                        }.chartForegroundStyleScale(["摄入": Theme.green, "消耗": Color.orange])
                            .chartXScale(domain: interval.start...interval.end)
                            .chartXSelection(value: $selected).frame(height: 230)
                        Text("kcal · 缺失数据留空，各项日均按各自有数据的天数计算")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("仅查看苹果健康活动消耗", isOn: $activityOnly)
                    Text("总消耗估算采用当前综合代谢 + 当日活动消耗；历史代谢会随资料调整而重新估算。当天数据截至当前时间。")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(visibleDays) { day in
                        Button {
                            if period == 2 { anchor = day.date; period = 1 }
                            else { selected = day.date }
                        } label: {
                            HStack {
                                Text(day.date.formatted(period == 2 ? .dateTime.month() : .dateTime.month().day()))
                                Spacer()
                                Text("摄入 \(text(day.intake))")
                                Text("消耗 \(text(activityOnly ? day.activity : day.total))")
                                Image(systemName: "chevron.right")
                            }.font(.subheadline).padding(.vertical, 8)
                        }
                    }
                    if period != 2, let selected {
                        Card {
                            Text(selected.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                            let meals = store.snapshot.meals(on: selected)
                            if meals.isEmpty { Text("当天未记录饮食") }
                            ForEach(meals) { meal in
                                Text("\(meal.kind.label) · \(meal.items.map(\.name).joined(separator: "、")) · \(Int(meal.totalKcal)) kcal")
                            }
                        }
                    }
                }.padding(20)
            }.navigationTitle("趋势")
                .onChange(of: period) { _, _ in selected = nil }
        }
    }
    private var visibleDays: [Day] { Array(buckets.reversed()) }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) { Text(title).font(.caption); Text(value).font(.title3.bold()) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
    private func move(_ amount: Int) {
        anchor = calendar.date(byAdding: component, value: amount, to: anchor) ?? anchor
        selected = nil
    }
}
