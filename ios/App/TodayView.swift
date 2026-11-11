import SwiftUI

struct TodayView: View {
    @Environment(\.appSkin) private var skin
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthService
    @Environment(\.scenePhase) private var scenePhase
    @State private var day = Date()
    @State private var manual = false
    @State private var profileEditor = false
    @State private var photo = false
    @State private var metabolism = false
    @State private var editing: Meal?
    @State private var chooseDate = false
    @State private var draftDay = Date()

    var body: some View {
        let meals = store.snapshot.meals(on: day)
        let intake = meals.reduce(0) { $0 + $1.totalKcal }
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    dateNavigation
                    intakeCard(intake)
                    if let profile = store.snapshot.profile {
                        MetabolismCard(profile: profile, assessment: store.snapshot.metabolism) { metabolism = true }
                    }
                    activityCard
                    mealList(meals)
                }.padding(.horizontal, Theme.gutter).padding(.vertical, 10)
            }.background(skin.background)
                .navigationTitle(Calendar.current.isDateInToday(day) ? "今日" : "饮食记录")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(skin.background, for: .navigationBar)
                .toolbar { ToolbarItem(placement: .principal) { BrandWordmark() } }
                .pageActions {
                    EqualActions {
                        Button("拍照记餐") { photo = true }
                            .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("meal.photo")
                        Button("手动添加") { manual = true }
                            .buttonStyle(OutlineButtonStyle()).accessibilityIdentifier("meal.manual")
                    }
                }
                .sheet(isPresented: $profileEditor) { ProfileEditor(onboarding: false) }
                .sheet(isPresented: $chooseDate) {
                    NavigationStack {
                        ScrollView {
                            Card {
                                DatePicker("记录日期", selection: $draftDay, in: ...Date(), displayedComponents: .date)
                                    .datePickerStyle(.graphical).environment(\.locale, Locale(identifier: "zh_CN"))
                            }.padding(Theme.gutter)
                        }.background(skin.background)
                            .navigationTitle("选择日期").navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭", systemImage: "xmark") { chooseDate = false }.labelStyle(.iconOnly) } }
                            .pageActions {
                                EqualActions {
                                    Button("今天") { draftDay = Date() }.buttonStyle(OutlineButtonStyle())
                                    Button("确认日期") { day = draftDay; chooseDate = false }.buttonStyle(PrimaryButtonStyle())
                                }
                            }
                    }.presentationDetents([.height(520), .large])
                }
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
        HStack(spacing: 8) {
            Button { draftDay = day; chooseDate = true } label: {
                HStack(spacing: 7) {
                    Text(day.formatted(.dateTime.month().day().weekday())).font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.down").font(.caption2)
                }.frame(minHeight: 44)
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            Label(store.cloudSyncing ? "同步中" : store.cloudMessage == "已同步" ? "已同步" : "待同步",
                  systemImage: store.cloudMessage == "已同步" ? "checkmark.icloud" : "icloud")
                .font(.caption).foregroundStyle(skin.accent).accessibilityLabel(store.cloudMessage)
        }
    }
    private func intakeCard(_ intake: Double) -> some View {
        Card(surface: skin.membershipBackground) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("今日摄入").font(.subheadline.weight(.semibold))
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(Int(intake.rounded()))").font(.system(size: 35, weight: .bold, design: .rounded))
                            .foregroundStyle(skin.accent).minimumScaleFactor(0.6).monospacedDigit()
                            .accessibilityIdentifier("intake.total")
                        Text("kcal").font(.caption).foregroundStyle(.secondary)
                    }
                    if let profile = store.snapshot.profile {
                        Text("目标 \(Int(profile.dailyTarget)) kcal").font(.caption).foregroundStyle(.secondary)
                        let remaining = profile.dailyTarget - intake
                        Text(remaining >= 0 ? "还可摄入 \(Int(remaining.rounded())) kcal" : "超过目标 \(Int((-remaining).rounded())) kcal")
                            .font(.caption.weight(.semibold)).foregroundStyle(remaining >= 0 ? skin.accent : Theme.orange)
                    } else {
                        Text("记下每一餐，慢慢看见变化").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(skin.softAccent, lineWidth: 9)
                    if let target = store.snapshot.profile?.dailyTarget, target > 0 {
                        let ratio = max(0, intake / target)
                        Circle().trim(from: 0, to: min(1, ratio))
                            .stroke(skin.accent, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text(ratio, format: .percent.precision(.fractionLength(0))).font(.subheadline.bold()).foregroundStyle(skin.accent)
                    } else {
                        Image(systemName: "fork.knife").font(.title3).foregroundStyle(skin.accent)
                    }
                }.frame(width: 76, height: 76).accessibilityHidden(true)
            }
            if store.snapshot.profile == nil {
                Divider()
                Button { profileEditor = true } label: {
                    HStack {
                        Text("完善资料，了解代谢与摄入目标").font(.caption.weight(.semibold))
                        Spacer(); Image(systemName: "arrow.up.right").font(.caption)
                    }
                }.accessibilityIdentifier("profile.open")
            }
        }
    }
    private var activityCard: some View {
        let cached = store.snapshot.activityDays.first { $0.day == ActivityDay.key(for: day) && $0.timeZone == TimeZone.current.identifier }
        let energy = health.activeKcal ?? cached?.activeKcal
        return Card {
            HStack(spacing: 11) {
                Image(systemName: "flame.fill").foregroundStyle(Theme.orange).font(.title3)
                    .frame(width: 38, height: 42).background(Theme.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text("活动消耗").font(.subheadline.weight(.semibold))
                    Text(energy == nil ? "连接苹果健康，补全每日消耗" : "苹果健康 · 日常活动与训练")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if !health.hasRequested {
                    Button("连接") { Task { await health.connect() } }.font(.caption.weight(.semibold))
                } else if health.refreshing { ProgressView() }
                else {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(energy.map { "\(Int($0.rounded()))" } ?? "—").font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("kcal").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if health.hasRequested && energy == nil {
                Text(health.message).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func mealList(_ meals: [Meal]) -> some View {
        Card {
            HStack { Text("今日饮食").font(.headline); Spacer(); Text("\(meals.count) 条记录").font(.caption).foregroundStyle(.secondary) }
            if meals.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "leaf").font(.system(size: 30)).foregroundStyle(skin.accent)
                    Text("从第一餐开始").font(.subheadline.weight(.semibold))
                    Text("拍张照片，或手动记录食物与热量").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 20)
            }
            ForEach(meals) { meal in
                Button { editing = meal } label: {
                    HStack(spacing: 11) {
                        MealThumbnail(url: store.photoURL(for: meal), symbol: meal.kind.symbol)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(meal.items.map(\.name).joined(separator: "、")).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text("\(meal.kind.label) · \(meal.consumedAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 3)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(meal.totalKcal.rounded()))").font(.system(size: 19, weight: .semibold, design: .rounded))
                            Text("kcal").font(.caption2).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }.foregroundStyle(.primary)
                }.buttonStyle(.plain)
                if meal.id != meals.last?.id { Divider() }
            }
        }
    }
}

struct MetabolismCard: View {
    @Environment(\.appSkin) private var skin
    let profile: Profile
    let assessment: MetabolismAssessment?
    var action: (() -> Void)?
    private var current: MetabolismAssessment? { assessment.flatMap { $0.matches(profile) ? $0 : nil } }
    var body: some View {
        Card {
            HStack {
                Text("静息代谢估算").font(.subheadline.weight(.semibold))
                Text("kcal/天").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if let action {
                    Button(action: action) { Image(systemName: "info.circle").frame(width: 44, height: 44) }
                        .accessibilityLabel("查看代谢估算依据")
                }
            }
            HStack(spacing: 8) {
                value("公式估算", profile.formulaKcal)
                value("AI 估算", current?.response.estimatedKcal)
                value("综合代谢", Metabolism.combined(profile: profile, assessment: current))
                    .foregroundStyle(skin.accent).padding(6)
                    .background(skin.softAccent, in: RoundedRectangle(cornerRadius: 10))
            }
            Text(current == nil ? "AI 尚未分析，暂用公式估算。" : (current!.canBlend(with: profile) ? "公式 80% + AI 20% · 产品参考估算" : "两者差异较大，暂用公式，请核对资料。"))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func value(_ label: String, _ number: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            if let number { Text(number, format: .number.precision(.fractionLength(0))).font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit() }
            else { Text("待分析").font(.subheadline).foregroundStyle(.secondary) }
        }.lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity, alignment: .center)
    }
}
