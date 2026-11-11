import SwiftUI
import StoreKit

struct MembershipCard: View {
    @Environment(\.appSkin) private var skin
    let active: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("轻记会员", systemImage: "crown.fill").font(.headline).symbolRenderingMode(.multicolor)
            Text("每周期 100 次 AI 分析").font(.subheadline).foregroundStyle(.secondary)
            NavigationLink {
                if active { MembershipManagementView() } else { MembershipPurchaseView() }
            } label: {
                Text(active ? "管理会员" : "开通会员")
            }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("membership.entry")
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background { MembershipBackdrop() }
    }
}

private struct MembershipBackdrop: View {
    @Environment(\.appSkin) private var skin

    var body: some View {
        RoundedRectangle(cornerRadius: 18).fill(skin.accent.opacity(0.13))
            .overlay(alignment: .trailing) {
                Image(systemName: "bowl.fill").font(.system(size: 70)).foregroundStyle(skin.accent.opacity(0.10))
                    .rotationEffect(.degrees(-14)).padding(.trailing, 18)
            }.accessibilityHidden(true)
    }
}

struct MembershipPurchaseView: View {
    @EnvironmentObject private var membership: MembershipModel
    @Environment(\.appSkin) private var skin
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image("BrandIcon").resizable().scaledToFit().frame(width: 78, height: 78)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                    Text("轻记会员").font(.largeTitle.bold())
                    if let product = membership.product {
                        Text("\(product.displayPrice) / 月").font(.system(size: 38, weight: .bold, design: .rounded))
                    } else {
                        Text(membership.status?.purchaseEnabled == true ? "正在读取订阅价格…" : "¥5.90 / 月")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        if membership.status?.purchaseEnabled != true {
                            Text("方案参考价").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.foregroundStyle(skin.accent).frame(maxWidth: .infinity)
                    .padding(.top, 16).padding(.bottom, 28)
                    .background(alignment: .bottom) {
                        Ellipse().fill(skin.accent.opacity(0.10)).frame(height: 105).rotationEffect(.degrees(-7))
                            .offset(y: 62).clipped().accessibilityHidden(true)
                    }
                Card {
                    benefit("每周期 100 次 AI 分析", icon: "bolt")
                    Divider()
                    benefit("自定义 AI 模型", icon: "chevron.left.forwardslash.chevron.right")
                    Divider()
                    benefit("会员专属皮肤", icon: "paintbrush")
                }
                if let message = membership.message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(18)
        }.background(skin.background)
            .navigationTitle("轻记会员").navigationBarTitleDisplayMode(.inline)
            .task { await membership.loadProduct() }
            .onChange(of: membership.status?.active) { _, active in if active == true { dismiss() } }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button(membership.busy ? "正在处理…" : "开通会员") { Task { await membership.purchase() } }
                        .buttonStyle(PrimaryButtonStyle()).disabled(membership.product == nil || membership.busy || membership.status?.active == true)
                    Text(membership.status?.purchaseEnabled == true ? "自动续费 · 可随时取消" : "会员订阅暂未开放")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("恢复购买") { Task { await membership.restore() } }
                        .font(.footnote.weight(.semibold)).disabled(membership.status?.purchaseEnabled != true || membership.busy)
                    HStack(spacing: 14) {
                        Link("订阅条款", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        NavigationLink("隐私政策") { PrivacyView() }
                    }.font(.caption2)
                }.padding(.horizontal, 18).padding(.vertical, 10).background(skin.background)
            }
    }
    private func benefit(_ title: String, icon: String) -> some View {
        Label { Text(title).font(.subheadline.weight(.semibold)) } icon: {
            Image(systemName: icon).foregroundStyle(skin.accent).frame(width: 32, height: 32)
                .background(skin.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct MembershipManagementView: View {
    @EnvironmentObject private var membership: MembershipModel
    @Environment(\.appSkin) private var skin
    @State private var manage = false
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let status = membership.status, status.active {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("会员有效", systemImage: "crown.fill").font(.title3.bold()).symbolRenderingMode(.multicolor)
                        if let date = status.renewalDate {
                            Text(status.willRenew == false ? "到期日期 \(date)" : "本周期截止 \(date)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(17).background { MembershipBackdrop() }
                    MembershipQuotaCard(status: status)
                    Card {
                        NavigationLink { CustomModelEntry() } label: { entry("自定义模型", icon: "chevron.left.forwardslash.chevron.right") }
                        Divider()
                        NavigationLink { AppearanceView() } label: { entry("会员皮肤", icon: "paintpalette") }
                    }.buttonStyle(.plain)
                } else {
                    NavigationLink("开通会员") { MembershipPurchaseView() }.buttonStyle(PrimaryButtonStyle())
                }
                if let message = membership.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }.padding(18)
        }.background(skin.background).navigationTitle("会员管理").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if membership.status?.active == true {
                    VStack(spacing: 10) {
                        Button { manage = true } label: { Text("管理订阅").frame(maxWidth: .infinity).padding(5) }
                            .buttonStyle(.bordered)
                        Button { Task { await membership.restore() } } label: { Text("恢复购买").frame(maxWidth: .infinity).padding(5) }
                            .buttonStyle(.bordered).disabled(membership.status?.purchaseEnabled != true || membership.busy)
                    }.padding(18).background(skin.background)
                }
            }
            .manageSubscriptionsSheet(isPresented: $manage)
            .onChange(of: manage) { _, shown in if !shown { Task { await membership.refresh() } } }
            .task { await membership.refresh() }
    }

    private func entry(_ title: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.frame(minHeight: 32).contentShape(Rectangle())
    }
}

struct MembershipQuotaCard: View {
    let status: MembershipStatus
    @Environment(\.appSkin) private var skin
    var body: some View {
        Card {
            HStack {
                Text(status.active ? "本周期剩余" : "免费体验剩余").font(.subheadline.weight(.semibold))
                Spacer()
                if status.active, let date = status.renewalDate {
                    Text(status.willRenew == false ? "\(date) 到期" : "\(date) 刷新")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(status.remaining)").font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(skin.accent)
                Text("/ \(status.limit) 次").font(.headline)
            }
            ProgressView(value: Double(status.remaining), total: Double(max(1, status.limit))).tint(skin.accent)
            if !status.active { Text("累计体验额度").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct BuiltInModelView: View {
    @EnvironmentObject private var membership: MembershipModel
    @Environment(\.appSkin) private var skin
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    HStack {
                        Image(systemName: "fish.fill").font(.title2).foregroundStyle(.blue)
                        Text("DeepSeek Flash").font(.headline)
                        Spacer()
                        if membership.status?.model == "builtIn" {
                            Text("当前使用").font(.caption.weight(.semibold)).padding(8)
                                .background(skin.accent.opacity(0.1), in: Capsule()).foregroundStyle(skin.accent)
                        } else if membership.status?.active == true {
                            Button("启用") { Task { await enable() } }.font(.subheadline.weight(.semibold))
                        }
                    }
                }
                if let status = membership.status { MembershipQuotaCard(status: status) }
                Text("支持的任务").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                Card {
                    Label("拍照识别", systemImage: "camera")
                    Divider()
                    Label("静息代谢", systemImage: "waveform.path.ecg")
                }
                Label("确认食物信息后重新估算，仍计为一次分析", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }.padding(18)
        }.background(skin.background).navigationTitle("内置 DeepSeek").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                NavigationLink {
                    if membership.status?.active == true { MembershipManagementView() }
                    else { MembershipPurchaseView() }
                } label: {
                    Text(membership.status?.active == true ? "查看会员权益" : "开通会员")
                }.buttonStyle(PrimaryButtonStyle()).padding(18).background(skin.background)
            }
            .task { await membership.refresh() }
    }
    private func enable() async {
        do { try await membership.update(model: "builtIn"); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct CustomModelEntry: View {
    @EnvironmentObject private var membership: MembershipModel
    @Environment(\.appSkin) private var skin
    var body: some View {
        if membership.status?.active == true || membership.status?.enabled == false {
            ModelSettingsView()
        } else {
            ScrollView {
                VStack(spacing: 18) {
                    Card {
                        Label("自定义模型", systemImage: "lock").font(.title2.bold())
                        Text("使用自己的 API Key，分别配置文字和图片模型。").foregroundStyle(.secondary)
                        Divider()
                        Label("编辑提示词", systemImage: "pencil")
                        Label("调试模型", systemImage: "terminal")
                        Label("查询余额", systemImage: "creditcard")
                    }
                    NavigationLink("开通会员使用") { MembershipPurchaseView() }.buttonStyle(PrimaryButtonStyle())
                }.padding(18)
            }.background(skin.background).navigationTitle("自定义模型").navigationBarTitleDisplayMode(.inline)
                .task { await membership.refresh() }
        }
    }
}
