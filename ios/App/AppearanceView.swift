import SwiftUI

enum AppSkin: String, CaseIterable, Identifiable, Codable {
    case classic, orange, blue
    var id: Self { self }
    var name: String {
        switch self {
        case .classic: "轻记经典"
        case .orange: "奶油暖橙"
        case .blue: "雾蓝简约"
        }
    }
    var accent: Color {
        switch self {
        case .classic: adaptive(light: UIColor(red: 0.035, green: 0.34, blue: 0.19, alpha: 1),
                                dark: UIColor(red: 0.43, green: 0.82, blue: 0.60, alpha: 1))
        case .orange: adaptive(light: UIColor(red: 0.65, green: 0.29, blue: 0.15, alpha: 1),
                               dark: UIColor(red: 1, green: 0.55, blue: 0.37, alpha: 1))
        case .blue: adaptive(light: UIColor(red: 0.19, green: 0.34, blue: 0.50, alpha: 1),
                             dark: UIColor(red: 0.56, green: 0.74, blue: 0.97, alpha: 1))
        }
    }
    var background: Color {
        switch self {
        case .classic: Theme.background
        case .orange: adaptive(light: UIColor(red: 1, green: 0.953, blue: 0.906, alpha: 1),
                               dark: UIColor(red: 0.12, green: 0.08, blue: 0.06, alpha: 1))
        case .blue: adaptive(light: UIColor(red: 0.937, green: 0.957, blue: 0.98, alpha: 1),
                             dark: UIColor(red: 0.06, green: 0.09, blue: 0.14, alpha: 1))
        }
    }
    var softAccent: Color { accent.opacity(0.08) }
    var membershipBackground: Color {
        self == .classic
            ? adaptive(light: UIColor(red: 0.91, green: 0.95, blue: 0.83, alpha: 1),
                       dark: UIColor(red: 0.11, green: 0.18, blue: 0.10, alpha: 1))
            : softAccent
    }
    var buttonFill: Color {
        switch self {
        case .classic: Theme.green
        case .orange: Color(red: 0.60, green: 0.27, blue: 0.12)
        case .blue: Color(red: 0.13, green: 0.31, blue: 0.48)
        }
    }
    private func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

private struct AppSkinKey: EnvironmentKey {
    static let defaultValue = AppSkin.classic
}

extension EnvironmentValues {
    var appSkin: AppSkin {
        get { self[AppSkinKey.self] }
        set { self[AppSkinKey.self] = newValue }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var label: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct AppearanceView: View {
    @EnvironmentObject private var membership: MembershipModel
    @Environment(\.appSkin) private var skin
    @AppStorage("qingji.appearanceMode") private var mode: AppearanceMode = .system

    var body: some View {
        ScrollView {
            VStack(spacing: 13) {
                ForEach(AppSkin.allCases) { theme in
                    NavigationLink {
                        SkinPreviewView(theme: theme)
                    } label: {
                        HStack(spacing: 15) {
                            thumbnail(theme)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(theme.name).font(.headline).foregroundStyle(.primary)
                                if (membership.status?.skin ?? .classic) == theme {
                                    Text("当前使用").font(.caption).foregroundStyle(theme.accent)
                                } else if theme != .classic {
                                    Text("会员").font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(theme.softAccent, in: Capsule()).foregroundStyle(theme.accent)
                                }
                            }
                            Spacer()
                            if (membership.status?.skin ?? .classic) == theme {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent)
                            } else {
                                Text("预览").font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                                    .padding(.horizontal, 13).padding(.vertical, 6)
                                    .overlay(Capsule().stroke(theme.accent, lineWidth: 1))
                            }
                        }.padding(12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.accent.opacity(0.24), lineWidth: 1))
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("skin.\(theme.rawValue)")
                }
                Card {
                    HStack {
                        Label("显示模式", systemImage: "moon").font(.subheadline.weight(.semibold))
                        Spacer()
                        Picker("显示模式", selection: $mode) {
                            ForEach(AppearanceMode.allCases) { option in Text(option.label).tag(option) }
                        }.labelsHidden().pickerStyle(.menu)
                    }
                }.padding(.top, 8)
            }.padding(18)
        }.background(skin.background).subpageNavigation(title: "外观")
            .task { await membership.refresh() }
    }

    private func thumbnail(_ theme: AppSkin) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日").font(.system(size: 12, weight: .bold))
                    Text("11月11日").font(.system(size: 8))
                }
                Spacer()
                Image(systemName: "bowl.fill").foregroundStyle(theme.accent).font(.caption)
            }
            HStack(spacing: 7) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日摄入").font(.system(size: 8))
                    Text("1,320").font(.system(size: 12, weight: .bold))
                    Text("目标 1,800 kcal").font(.system(size: 7))
                }
                Circle().trim(from: 0, to: 0.73).stroke(theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 23, height: 23)
            }.padding(6).background(Theme.card, in: RoundedRectangle(cornerRadius: 7))
            Label("活动消耗 · 380 kcal", systemImage: "figure.run").font(.system(size: 8, weight: .semibold))
                .padding(4).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 5))
        }.padding(8).frame(width: 118, height: 119).background(theme.background, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}

private struct SkinPreviewView: View {
    let theme: AppSkin
    @EnvironmentObject private var membership: MembershipModel
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var error: String?
    private var unlocked: Bool { theme == .classic || membership.status?.active == true }
    private var inUse: Bool { (membership.status?.skin ?? .classic) == theme }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("今日").font(.largeTitle.bold())
                        Text("11月11日").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image("BrandIcon").resizable().frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 12))
                }.padding(.horizontal, 7)
                Card {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("今日摄入").font(.subheadline.bold())
                            Text("1,320 kcal").font(.system(size: 31, weight: .bold, design: .rounded))
                            Text("目标 1,800 kcal").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ZStack {
                            Circle().stroke(theme.softAccent, lineWidth: 8)
                            Circle().trim(from: 0, to: 0.73).stroke(theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }.frame(width: 88, height: 88).accessibilityHidden(true)
                    }
                }
                Card { LabeledContent { Text("380 kcal") } label: { Label("活动消耗", systemImage: "figure.run").foregroundStyle(theme.accent) } }
                Card {
                    Text("今日饮食").font(.headline)
                    meal("早餐", "酸奶", "240 kcal", "ThemeYogurt")
                    Divider()
                    meal("午餐", "米饭", "520 kcal", "ThemeRice")
                    EqualActions {
                        Text("拍照记餐").actionPreview(theme, filled: true)
                        Text("手动添加").actionPreview(theme, filled: false)
                    }.accessibilityHidden(true)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }.padding(12).background(theme.softAccent, in: RoundedRectangle(cornerRadius: 24)).padding(18)
        }.background(theme.background)
            .navigationTitle("皮肤预览").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .pageActions {
                Group {
                    if unlocked {
                        Button(inUse ? "当前使用" : busy ? "正在应用…" : "应用皮肤") { Task { await apply() } }
                            .buttonStyle(PrimaryButtonStyle()).disabled(busy || inUse)
                    } else {
                        NavigationLink("开通会员使用") { MembershipPurchaseView() }.buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
            .environment(\.appSkin, theme).tint(theme.accent)
    }

    private func meal(_ title: String, _ food: String, _ kcal: String, _ asset: String) -> some View {
        HStack(spacing: 10) {
            Image(asset).resizable().scaledToFill().frame(width: 52, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(food).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(kcal).font(.subheadline)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }

    private func apply() async {
        busy = true
        defer { busy = false }
        do { try await membership.update(skin: theme); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
