import SwiftUI
import StoreKit

struct MembershipCard: View {
    @Environment(\.appSkin) private var skin
    let active: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("轻记会员").font(.headline)
                    Text("每周期 100 次 AI 分析").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            NavigationLink {
                if active { MembershipManagementView() } else { MembershipPurchaseView() }
            } label: {
                Text(active ? "管理会员" : "开通会员")
            }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("membership.entry")
        }.padding(16).background(skin.softAccent, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct MembershipPurchaseView: View {
    @EnvironmentObject private var membership: MembershipModel
    @Environment(\.appSkin) private var skin
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image("BrandIcon").resizable().scaledToFit().frame(width: 78, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 22)).padding(.top, 16)
                Text("轻记会员").font(.largeTitle.bold()).foregroundStyle(skin.accent)
                if let product = membership.product {
                    Text("\(product.displayPrice) / 月").font(.system(size: 38, weight: .bold, design: .rounded))
                } else {
                    Text(membership.status?.purchaseEnabled == true ? "正在读取订阅价格…" : "¥5.90 / 月")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    if membership.status?.purchaseEnabled != true {
                        Text("方案参考价").font(.caption).foregroundStyle(.secondary)
                    }
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
                    Card {
                        Label("会员有效", systemImage: "crown.fill").font(.title3.bold())
                        if let date = status.renewalDate {
                            Text(status.willRenew == false ? "到期日期 \(date)" : "本周期截止 \(date)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    MembershipQuotaCard(status: status)
                    Card {
                        NavigationLink { ModelSettingsView() } label: { Label("自定义模型", systemImage: "chevron.left.forwardslash.chevron.right") }
                        Divider()
                        NavigationLink { AppearanceView() } label: { Label("会员皮肤", systemImage: "paintpalette") }
                    }
                    Button("管理订阅") { manage = true }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                    Button("恢复购买") { Task { await membership.restore() } }
                        .disabled(membership.status?.purchaseEnabled != true || membership.busy)
                } else {
                    NavigationLink("开通会员") { MembershipPurchaseView() }.buttonStyle(PrimaryButtonStyle())
                }
                if let message = membership.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }.padding(18)
        }.background(skin.background).navigationTitle("会员管理").navigationBarTitleDisplayMode(.inline)
            .manageSubscriptionsSheet(isPresented: $manage)
            .onChange(of: manage) { _, shown in if !shown { Task { await membership.refresh() } } }
            .task { await membership.refresh() }
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
                        Label("DeepSeek Flash", systemImage: "cube").font(.headline)
                        Spacer()
                        if membership.status?.model == "builtIn" {
                            Text("当前使用").font(.caption.weight(.semibold)).padding(8)
                                .background(skin.accent.opacity(0.1), in: Capsule()).foregroundStyle(skin.accent)
                        } else {
                            Button("启用") { Task { await enable() } }.font(.subheadline.weight(.semibold))
                        }
                    }
                }
                if let status = membership.status { MembershipQuotaCard(status: status) }
                Card {
                    Text("支持的任务").font(.caption).foregroundStyle(.secondary)
                    Label("拍照识别", systemImage: "camera")
                    Divider()
                    Label("静息代谢", systemImage: "waveform.path.ecg")
                }
                Label("确认食物信息后重新估算，仍计为一次分析", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                NavigationLink {
                    if membership.status?.active == true { MembershipManagementView() }
                    else { MembershipPurchaseView() }
                } label: {
                    Text(membership.status?.active == true ? "查看会员权益" : "开通会员")
                }.buttonStyle(PrimaryButtonStyle())
            }.padding(18)
        }.background(skin.background).navigationTitle("内置 DeepSeek").navigationBarTitleDisplayMode(.inline)
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
