import SwiftUI
import Charts

struct HealthSettingsView: View {
    @Environment(\.appSkin) private var skin
    @EnvironmentObject private var health: HealthService
    @EnvironmentObject private var store: AppStore
    @State private var selected: Set<String> = []
    @State private var syncing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(surface: skin.membershipBackground) {
                    Label(health.hasRequested ? "已设置苹果健康" : "连接苹果健康", systemImage: "heart.fill").font(.headline)
                    if let updated = health.lastUpdated { Text("最近同步 \(updated.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                    else { Text(health.message).font(.caption).foregroundStyle(.secondary) }
                }
                Text("选择同步指标").font(.headline)
                Card {
                    ForEach(HealthMetric.allCases) { metric in
                        Toggle(isOn: Binding(get: { selected.contains(metric.rawValue) }, set: { enabled in
                            if enabled { selected.insert(metric.rawValue) } else { selected.remove(metric.rawValue) }
                        })) {
                            Label(metric.label, systemImage: metric.symbol)
                        }.tint(skin.accent).frame(minHeight: 44)
                        if metric != HealthMetric.allCases.last { Divider() }
                    }
                }
                Text("可在健康 App 中调整读取权限。所选指标的每日汇总会同步到当前账号。关闭后停止读取，已保存记录继续保留。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(Theme.gutter)
        }.background(skin.background).subpageNavigation(title: "苹果健康")
            .pageActions {
                Button(syncing ? "正在同步…" : "保存并同步") {
                    syncing = true
                    Task { await health.synchronize(selected, into: store); syncing = false }
                }.buttonStyle(PrimaryButtonStyle()).disabled(syncing)
            }
            .onAppear { selected = health.selected }
    }
}

struct HealthSummary: View {
    @Environment(\.appSkin) private var skin
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthService
    let date: Date

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach([HealthMetric.steps, .weight, .sleep]) { metric in
                    NavigationLink { HealthTrendView(metric: metric) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Image(systemName: metric.symbol).foregroundStyle(skin.accent)
                            Text(metric.label).font(.caption).foregroundStyle(.secondary)
                            Text(value(metric)).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
                        }.frame(maxWidth: .infinity, minHeight: 82, alignment: .leading).padding(10)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
            }
            NavigationLink { HealthDetailsView(date: date) } label: {
                Card { HStack { Label("查看健康详情", systemImage: "heart"); Spacer(); Image(systemName: "chevron.right") } }
            }.buttonStyle(.plain)
        }
    }

    private func value(_ metric: HealthMetric) -> String {
        guard health.selected.contains(metric.rawValue) else { return "未同步" }
        let day = ActivityDay.key(for: date)
        guard let record = store.snapshot.healthMetrics.first(where: { $0.day == day && $0.metric == metric.rawValue && $0.timeZone == TimeZone.current.identifier }) else { return "暂无数据" }
        return healthValue(record.value, metric: metric)
    }
}

func healthValue(_ value: Double, metric: HealthMetric) -> String {
    switch metric {
    case .activity: "\(Int(value.rounded())) kcal"
    case .steps: "\(Int(value.rounded()).formatted()) 步"
    case .weight: "\(value.formatted(.number.precision(.fractionLength(1)))) kg"
    case .sleep: "\(value.formatted(.number.precision(.fractionLength(1)))) 小时"
    case .heartRate: "\(Int(value.rounded())) 次/分"
    }
}

struct HealthDetailsView: View {
    @Environment(\.appSkin) private var skin
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthService
    @State var date: Date

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    Spacer(); Text(date.formatted(.dateTime.month().day().weekday())).font(.headline); Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(Calendar.current.isDateInToday(date))
                }.background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(HealthMetric.allCases) { metric in
                        NavigationLink { HealthTrendView(metric: metric) } label: {
                            Card(surface: skin.softAccent) {
                                Image(systemName: metric.symbol).font(.title3).foregroundStyle(skin.accent)
                                Text(metric.label).font(.subheadline)
                                Text(value(metric)).font(.title3.bold()).foregroundStyle(skin.accent)
                                Text(health.selected.contains(metric.rawValue) ? "每日汇总" : "未同步").font(.caption).foregroundStyle(.secondary)
                            }.frame(minHeight: 140)
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(Theme.gutter)
        }.background(skin.background).subpageNavigation(title: "健康详情")
            .pageActions { NavigationLink("管理同步指标") { HealthSettingsView() }.buttonStyle(PrimaryButtonStyle()) }
    }

    private func move(_ amount: Int) { date = Calendar.current.date(byAdding: .day, value: amount, to: date) ?? date }
    private func value(_ metric: HealthMetric) -> String {
        guard health.selected.contains(metric.rawValue) else { return "未同步" }
        let day = ActivityDay.key(for: date)
        if metric == .activity {
            guard let record = store.snapshot.activityDays.first(where: { $0.day == day && $0.timeZone == TimeZone.current.identifier }) else { return "暂无数据" }
            return healthValue(record.activeKcal, metric: metric)
        }
        guard let record = store.snapshot.healthMetrics.first(where: { $0.day == day && $0.metric == metric.rawValue && $0.timeZone == TimeZone.current.identifier }) else { return "暂无数据" }
        return healthValue(record.value, metric: metric)
    }
}

struct HealthTrendView: View {
    @Environment(\.appSkin) private var skin
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthService
    @State var metric: HealthMetric
    @State private var period = TrendPeriod.month
    @State private var anchor = Date()

    private var points: [HealthMetricRecord] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: period.component, for: anchor) else { return [] }
        if metric == .activity {
            return store.snapshot.activityDays.filter { $0.timeZone == calendar.timeZone.identifier }.compactMap { item in
                guard let date = date(item.day), interval.contains(date) else { return nil }
                return HealthMetricRecord(id: item.id, day: item.day, timeZone: item.timeZone, metric: metric.rawValue, value: item.activeKcal, updatedAt: item.updatedAt)
            }.sorted { $0.day < $1.day }
        }
        return store.snapshot.healthMetrics.filter { $0.metric == metric.rawValue && $0.timeZone == calendar.timeZone.identifier && date($0.day).map { interval.contains($0) } == true }.sorted { $0.day < $1.day }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PageSegments(selection: $period, options: TrendPeriod.allCases.map { ($0.label, $0) }).frame(height: 34)
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    Spacer()
                    Text(period == .year ? anchor.formatted(.dateTime.year()) : anchor.formatted(.dateTime.year().month().day()))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .disabled((Calendar.current.dateInterval(of: period.component, for: anchor)?.end ?? Date()) > Date())
                }
                Card {
                    Picker("指标", selection: $metric) { ForEach(HealthMetric.allCases) { Text($0.label).tag($0) } }
                        .pickerStyle(.menu)
                }
                Card {
                    if !health.selected.contains(metric.rawValue) { Text("未同步").foregroundStyle(.secondary) }
                    else if points.isEmpty { Text("暂无可读取数据").foregroundStyle(.secondary) }
                    else {
                        Chart(points) { point in
                            if let day = date(point.day) {
                                LineMark(x: .value("日期", day), y: .value(metric.label, point.value)).foregroundStyle(skin.accent)
                                PointMark(x: .value("日期", day), y: .value(metric.label, point.value)).foregroundStyle(skin.accent)
                            }
                        }.frame(height: 240)
                    }
                }
                if let first = points.first, let last = points.last, points.count > 1 {
                    Card { LabeledContent("本期变化", value: healthValue(last.value - first.value, metric: metric)) }
                }
                NavigationLink("管理同步指标") { HealthSettingsView() }.buttonStyle(OutlineButtonStyle())
            }.padding(Theme.gutter)
        }.background(skin.background).subpageNavigation(title: "健康趋势")
    }
    private func date(_ value: String) -> Date? {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
    private func move(_ amount: Int) {
        anchor = Calendar.current.date(byAdding: period.component, value: amount, to: anchor) ?? anchor
    }
}
