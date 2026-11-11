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
        case .classic: Theme.green
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
                                    .padding(8).background(theme.softAccent, in: Capsule())
                            }
                        }.padding(12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.accent.opacity(0.24), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
                Card {
                    Picker(selection: $mode) {
                        ForEach(AppearanceMode.allCases) { option in Text(option.label).tag(option) }
                    } label: { Label("显示模式", systemImage: "moon") }
                }.padding(.top, 8)
            }.padding(18)
        }.background(skin.background).navigationTitle("外观").navigationBarTitleDisplayMode(.inline)
            .task { await membership.refresh() }
    }

    private func thumbnail(_ theme: AppSkin) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("今日").font(.system(size: 10, weight: .bold))
            HStack(spacing: 7) {
                Text("1,320").font(.system(size: 12, weight: .bold))
                Circle().trim(from: 0, to: 0.73).stroke(theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 23, height: 23)
            }.padding(6).background(Theme.card, in: RoundedRectangle(cornerRadius: 7))
            Capsule().fill(theme.accent).frame(height: 5)
        }.padding(8).frame(width: 92, height: 88).background(theme.background, in: RoundedRectangle(cornerRadius: 12))
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                Text(theme.name).font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                Text("今日").font(.largeTitle.bold())
                Text("11月11日").foregroundStyle(.secondary)
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
                        }.frame(width: 65, height: 65).accessibilityHidden(true)
                    }
                }
                Card { LabeledContent { Text("380 kcal") } label: { Label("活动消耗", systemImage: "figure.run").foregroundStyle(theme.accent) } }
                Card {
                    Text("今日饮食").font(.headline)
                    meal("早餐", "酸奶和水果", "420 kcal", "cup.and.saucer")
                    Divider()
                    meal("午餐", "鸡肉饭", "900 kcal", "fork.knife")
                    Label("拍照记餐", systemImage: "camera").frame(maxWidth: .infinity).padding(10)
                        .background(theme.softAccent, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(theme.accent)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }.padding(18)
        }.background(theme.background)
            .navigationTitle("皮肤预览").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Group {
                    if unlocked {
                        Button(busy ? "正在应用…" : "应用皮肤") { Task { await apply() } }
                            .buttonStyle(PrimaryButtonStyle()).disabled(busy)
                    } else {
                        NavigationLink("开通会员使用") { MembershipPurchaseView() }.buttonStyle(PrimaryButtonStyle())
                    }
                }.padding(18).background(theme.background)
            }
            .environment(\.appSkin, theme).tint(theme.accent)
    }

    private func meal(_ title: String, _ food: String, _ kcal: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(theme.accent).frame(width: 38, height: 38)
                .background(theme.softAccent, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(food).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(kcal).font(.subheadline)
        }
    }

    private func apply() async {
        busy = true
        defer { busy = false }
        do { try await membership.update(skin: theme); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
