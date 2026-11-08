import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthService
    @Environment(\.scenePhase) private var scenePhase
    @State private var day = Date()
    @State private var manual = false
    @State private var profileEditor = false
    @State private var photo = false
    @State private var metabolism = false
    @State private var editing: Meal?
    private var meals: [Meal] { store.snapshot.meals(on: day) }
    private var intake: Double { meals.reduce(0) { $0 + $1.totalKcal } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dateNavigation
                    if let profile = store.snapshot.profile {
                        intakeCard(profile)
                        MetabolismCard(profile: profile, assessment: store.snapshot.metabolism) { metabolism = true }
                    }
                    if store.snapshot.profile == nil {
                        Button("完善个人资料，查看代谢估算") { profileEditor = true }
                            .accessibilityIdentifier("profile.open")
                        Card {
                            Text("已记录摄入")
                            Text("\(Int(intake)) kcal").font(.largeTitle.bold()).accessibilityIdentifier("intake.total")
                        }
                    }
                    Text(store.cloudMessage).font(.caption).foregroundStyle(.secondary)
                    activityCard
                    mealList
                }.padding(.horizontal, 18).padding(.bottom, 16)
            }
            .background(Theme.background)
            .navigationTitle(Calendar.current.isDateInToday(day) ? "今日" : "饮食记录")
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button { photo = true } label: { Label("拍照记餐", systemImage: "camera") }
                        .buttonStyle(PrimaryButtonStyle())
                    Button { manual = true } label: {
                        Label("手动添加", systemImage: "plus").font(.headline).padding(.vertical, 15).padding(.horizontal, 16)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.green, lineWidth: 1))
                    }
                    .accessibilityIdentifier("meal.manual")
                }.padding(.horizontal, 18).padding(.vertical, 10).background(.bar)
            }
            .sheet(isPresented: $profileEditor) { ProfileEditor(onboarding: false) }
            .refreshable { await health.refresh(for: day) }
            .task { await health.refresh(for: day) }
            .onChange(of: day) { _, value in Task { await health.refresh(for: value) } }
            .onChange(of: scenePhase) { _, value in if value == .active { Task { await health.refresh(for: day) } } }
            .sheet(isPresented: $manual) { MealEditor(initialDate: day) }
            .sheet(isPresented: $photo) { PhotoMealView(initialDate: day) }
            .sheet(item: $editing) { meal in MealEditor(existing: meal, initialDate: day) }
            .sheet(isPresented: $metabolism) { MetabolismDetailView() }
        }
    }

    private var dateNavigation: some View {
        HStack {
            Button { moveDay(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                .accessibilityLabel("前一天")
            DatePicker("记录日期", selection: $day, in: ...Date(), displayedComponents: .date)
                .labelsHidden().datePickerStyle(.compact).environment(\.locale, Locale(identifier: "zh_CN"))
            Spacer()
            if !Calendar.current.isDateInToday(day) { Button("今天") { day = Date() }.font(.subheadline) }
            Button { moveDay(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                .disabled(Calendar.current.isDateInToday(day)).accessibilityLabel("后一天")
        }
    }

    private func moveDay(_ offset: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: offset, to: day) { day = min(next, Date()) }
    }

    private func intakeCard(_ profile: Profile) -> some View {
        Card {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("已记录摄入").font(.headline)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(intake, format: .number.precision(.fractionLength(0))).font(.system(size: 43, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).accessibilityIdentifier("intake.total")
                        Text("kcal").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("目标 \(Int(profile.dailyTarget)) kcal").font(.subheadline).foregroundStyle(.secondary)
                    let remaining = profile.dailyTarget - intake
                    Text(remaining >= 0 ? "还可摄入 \(Int(remaining.rounded())) kcal" : "超过目标 \(Int((-remaining).rounded())) kcal")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(remaining >= 0 ? Theme.green : .orange)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 10)
                    Circle().trim(from: 0, to: min(1, intake / profile.dailyTarget))
                        .stroke(Theme.green, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: "fork.knife").font(.title2).foregroundStyle(Theme.green)
                }.frame(width: 82, height: 82).accessibilityHidden(true)
            }
            Text("仅统计已保存的饮食，漏记不会自动补算。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var activityCard: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "flame.fill").font(.title).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 5) {
                    Text("活动消耗").font(.headline)
                    Text(health.message).font(.caption).foregroundStyle(.secondary)
                    if let time = health.lastUpdated, health.activeKcal != nil {
                        Text("更新于 \(time.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if health.refreshing { ProgressView() }
                else if let value = health.activeKcal { Text("\(Int(value.rounded())) kcal").font(.headline).monospacedDigit() }
                else if let cached = store.snapshot.activityDays.first(where: {
                    $0.day == ActivityDay.key(for: day) && $0.timeZone == TimeZone.current.identifier
                }) {
                    VStack(alignment: .trailing) {
                        Text("\(Int(cached.activeKcal.rounded())) kcal").font(.headline).monospacedDigit()
                        Text("已保存汇总").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                else { Text("—").foregroundStyle(.secondary) }
            }
            if !health.hasRequested {
                Button("连接苹果健康") { Task { await health.connect() } }.font(.subheadline.weight(.semibold))
            } else {
                Text("活动值已包含相应训练，不另加跑步或步数热量。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var mealList: some View {
        Card {
            HStack { Text("当天饮食").font(.headline); Spacer(); Text("\(meals.count) 条记录").font(.caption).foregroundStyle(.secondary) }
            if meals.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "fork.knife").font(.system(size: 32)).foregroundStyle(Theme.green)
                    Text("从记录第一餐开始").font(.headline)
                    Text("拍张照片，或直接输入热量。也可以切换日期补记。")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                ForEach(meals) { meal in
                    Button { editing = meal } label: {
                        HStack(spacing: 12) {
                            if let image = store.photo(for: meal) {
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                Image(systemName: meal.kind.symbol).font(.title2).foregroundStyle(Theme.green)
                                    .frame(width: 48, height: 48).background(Theme.softGreen, in: RoundedRectangle(cornerRadius: 12))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(meal.kind.label).font(.headline)
                                Text(meal.items.map(\.name).joined(separator: "、")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Text(meal.consumedAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(meal.totalKcal.rounded())) kcal").font(.subheadline.weight(.semibold)).monospacedDigit()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }.foregroundStyle(.primary)
                    }.buttonStyle(.plain)
                    if meal.id != meals.last?.id { Divider() }
                }
            }
        }
    }
}

struct MetabolismCard: View {
    let profile: Profile
    let assessment: MetabolismAssessment?
    let action: () -> Void
    private var current: MetabolismAssessment? { assessment.flatMap { $0.matches(profile) ? $0 : nil } }
    var body: some View {
        Card {
            HStack { Text("静息代谢估算").font(.headline); Spacer(); Button(action: action) { Image(systemName: "info.circle") }.accessibilityLabel("查看代谢估算依据") }
            HStack {
                value("公式估算", profile.formulaKcal)
                Spacer()
                Divider().frame(height: 42)
                Spacer()
                value("AI 估算", current?.response.estimatedKcal)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("综合代谢").font(.subheadline.weight(.semibold))
                Spacer()
                Text("≈ \(Int(Metabolism.combined(profile: profile, assessment: current).rounded()))")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("kcal/天").font(.caption)
            }.foregroundStyle(Theme.green).padding(12).background(Theme.softGreen, in: RoundedRectangle(cornerRadius: 12))
            Text(current == nil ? "AI 尚未分析，综合值暂用公式估算。" : (current!.canBlend(with: profile) ? "公式 80% + AI 20% · 产品参考规则，未经临床验证" : "两者差异较大，综合值暂用公式，请核对资料。"))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func value(_ label: String, _ number: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            if let number { Text(number, format: .number.precision(.fractionLength(0))).font(.title2.bold()).monospacedDigit() }
            else { Text("待分析").font(.title3).foregroundStyle(.secondary) }
            Text("kcal/天").font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
