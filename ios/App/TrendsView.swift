import SwiftUI

@MainActor
final class TrendsModel: ObservableObject {
    struct Key: Hashable {
        let period: Int
        let start: Date
        let revision: Int
        let zone: String
        let today: Date
    }
    @Published private(set) var report: TrendReport?
    @Published private(set) var loadedKey: Key?
    private var cache: [Key: TrendReport] = [:]

    func load(key: Key, snapshot: AppSnapshot, period: TrendPeriod, anchor: Date, calendar: Calendar) async {
        if let cached = cache[key] { report = cached; loadedKey = key; return }
        let worker = Task.detached(priority: .userInitiated) {
            try TrendReport.build(snapshot: snapshot, period: period, anchor: anchor, calendar: calendar)
        }
        do {
            let value = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            if cache.count >= 6 { cache.removeAll(keepingCapacity: true) }
            cache[key] = value
            report = value; loadedKey = key
        } catch { /* A newer range or another screen owns the next request. */ }
    }
}

struct TrendsView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var model = TrendsModel()
    @State private var period = TrendPeriod.week
    @State private var anchor = Date()
    @State private var activityOnly = true
    @State private var selectedSlot: Int?
    private var calendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    private var key: TrendsModel.Key {
        .init(period: period.rawValue, start: calendar.dateInterval(of: period.component, for: anchor)!.start,
              revision: store.dataRevision, zone: calendar.timeZone.identifier, today: calendar.startOfDay(for: Date()))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    HStack { Text("看见每一天的变化").font(.subheadline).foregroundStyle(.secondary); Spacer() }
                    Picker("范围", selection: $period) {
                        ForEach(TrendPeriod.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("trends.period")
                    if model.loadedKey == key, let report = model.report { content(report) }
                    else { ProgressView("正在整理记录…").frame(maxWidth: .infinity, minHeight: 300) }
                }.padding(18)
            }.background(Theme.background)
                .navigationTitle("趋势").navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Theme.background, for: .navigationBar)
                .task(id: key) { await model.load(key: key, snapshot: store.snapshot, period: period, anchor: anchor, calendar: calendar) }
                .onChange(of: key) { _, _ in selectedSlot = nil }
        }
    }

    @ViewBuilder private func content(_ report: TrendReport) -> some View {
        HStack {
            Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 40) }.accessibilityLabel("上一时段")
            Spacer(minLength: 4)
            Text(report.title).font(.subheadline.weight(.semibold)).accessibilityIdentifier("trends.range")
            Spacer(minLength: 4)
            Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 40) }
                .disabled(report.interval.end > Date()).accessibilityLabel("下一时段")
        }
        HStack(spacing: 10) {
            metric("日均摄入", number(report.intakeAverage), color: Theme.green)
            metric(activityOnly ? "日均活动" : "日均总消耗", number(activityOnly ? report.activityAverage : report.totalAverage), color: Theme.orange)
            metric("记录天数", "\(report.recordedDays)/\(report.elapsedDays)", color: .primary)
        }
        Card {
            HStack {
                Text(period == .year ? "各月日均热量" : "每日热量").font(.headline)
                Spacer()
                Text("kcal").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                legend("摄入", Theme.green); legend(activityOnly ? "活动消耗" : "总消耗估算", Theme.orange)
            }
            EnergyChart(buckets: report.buckets, activityOnly: activityOnly, selectedSlot: selectedSlot) { bucket in
                if period == .year { anchor = bucket.date; period = .month }
                else { selectedSlot = bucket.slot }
            }.frame(height: 200)
            Text(!report.hasData ? "这个时段还没有记录，回到今日记下第一餐吧。" :
                period == .year ? "点击柱状图查看该月 · 未记录的数据留空" : "点击柱状图查看当日 · 未记录的数据留空")
                .font(.caption).foregroundStyle(.secondary)
        }
        Card {
            Toggle(isOn: $activityOnly) {
                Label("仅看活动消耗", systemImage: "flame").font(.subheadline.weight(.medium))
            }
            DisclosureGroup("数据如何计算") {
                Text("总消耗 ≈ 当前综合代谢 + 当日苹果健康活动能量。未填写资料或未获得活动能量时留空。历史总消耗随资料调整而重新估算；当天截至当前时间。日均按各项有数据的天数分别计算。")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
            }.font(.caption)
        }
        if let slot = selectedSlot, let bucket = report.buckets.first(where: { $0.slot == slot }), period != .year {
            Card {
                Text(bucket.date.formatted(.dateTime.month().day())).font(.headline)
                if bucket.meals.isEmpty { Text("当天未记录饮食").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(bucket.meals) { meal in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(meal.items.map(\.name).joined(separator: "、")).font(.subheadline).lineLimit(2)
                            Text(meal.kind.label).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(meal.totalKcal.rounded())) kcal").font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        Card {
            Text(period == .year ? "月度明细" : "每日明细").font(.headline)
            ForEach(report.buckets.reversed().filter { $0.date <= Date() }) { bucket in
                Button {
                    if period == .year { anchor = bucket.date; period = .month }
                    else { selectedSlot = bucket.slot }
                } label: {
                    HStack {
                        Text(bucket.date.formatted(period == .year ? .dateTime.month() : .dateTime.month().day()))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(number(bucket.intake)).foregroundStyle(Theme.green)
                        Text("/ \(number(activityOnly ? bucket.activity : bucket.total))").foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }.font(.subheadline).padding(.vertical, 7)
                }.buttonStyle(.plain)
            }
            Text("摄入 / 消耗 · kcal").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func move(_ amount: Int) { anchor = calendar.date(byAdding: period.component, value: amount, to: anchor) ?? anchor }
    private func number(_ value: Double?) -> String { value.map { String(Int($0.rounded())) } ?? "—" }
    private func metric(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.system(size: 23, weight: .bold, design: .rounded)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.65).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 7, height: 7); Text(label).font(.caption2).foregroundStyle(.secondary) }
    }
}

/// At most 62 bars. Discrete slots avoid date-scale and gesture reconstruction between ranges.
private struct EnergyChart: View {
    let buckets: [TrendBucket]
    let activityOnly: Bool
    let selectedSlot: Int?
    let select: (TrendBucket) -> Void
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let width = max(1, size.width - 34)
                let top = 8.0
                let height = max(1, size.height - 38)
                let maximum = buckets.flatMap { [$0.intake ?? 0, (activityOnly ? $0.activity : $0.total) ?? 0] }.max() ?? 0
                let step = maximum > 1000 ? 500.0 : maximum > 200 ? 100.0 : 50.0
                let ceiling = max(step * 4, ceil(maximum / step) * step)
                for tick in 0...4 {
                    let y = top + height * (1 - Double(tick) / 4)
                    var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: width, y: y))
                    context.stroke(line, with: .color(.secondary.opacity(0.13)), lineWidth: 0.7)
                    context.draw(Text("\(Int(ceiling * Double(tick) / 4))").font(.system(size: 10)).foregroundColor(.secondary),
                                 at: CGPoint(x: width + 5, y: y), anchor: .leading)
                }
                let slot = width / Double(max(1, buckets.count))
                let barWidth = min(14, slot * 0.32)
                for bucket in buckets {
                    let x = (Double(bucket.slot) + 0.5) * slot
                    if selectedSlot == bucket.slot {
                        context.fill(Path(roundedRect: CGRect(x: x - slot / 2, y: top, width: slot, height: height), cornerRadius: 4),
                                     with: .color(Theme.softGreen))
                    }
                    let values: [(Double?, Color, Double)] = [(bucket.intake, Theme.green, -barWidth - 1),
                        (activityOnly ? bucket.activity : bucket.total, Theme.orange, 1)]
                    for (value, color, offset) in values {
                        if let value, value > 0 {
                            let h = max(1, height * min(1, value / ceiling))
                            let rect = CGRect(x: x + offset, y: top + height - h, width: barWidth, height: h)
                            context.fill(Path(roundedRect: rect, cornerRadius: min(3, barWidth / 2)), with: .color(color))
                        }
                    }
                    let stride = buckets.count <= 12 ? (buckets.count == 12 ? 2 : 1) : 5
                    if bucket.slot % stride == 0 || bucket.slot == buckets.count - 1 {
                        context.draw(Text(bucket.label).font(.system(size: 10)).foregroundColor(.secondary),
                                     at: CGPoint(x: x, y: top + height + 17))
                    }
                }
            }.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { event in
                let width = max(1, geometry.size.width - 34)
                guard event.location.x >= 0, event.location.x < width, !buckets.isEmpty else { return }
                let index = min(buckets.count - 1, Int(event.location.x / width * Double(buckets.count)))
                select(buckets[index])
            })
        }.accessibilityLabel("摄入与消耗柱状图，详细数值请查看下方明细")
    }
}
