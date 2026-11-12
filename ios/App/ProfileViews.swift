import SwiftUI
import UIKit

struct ProfileEditor: View {
    @Environment(\.appSkin) private var skin
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var session: AccountSession
    @Environment(\.dismiss) private var dismiss
    let onboarding: Bool
    @State private var sex = BiologicalSex.male
    @State private var age = "30"
    @State private var height = "175"
    @State private var weight = "70"
    @State private var target = "1800"
    @State private var error: String?

    private var profile: Profile? {
        guard let age = Int(age), let height = NumberText.parse(height), let weight = NumberText.parse(weight),
              let target = NumberText.parse(target) else { return nil }
        let value = Profile(sex: sex, age: age, heightCM: height, weightKG: weight, dailyTarget: target)
        return value.isValid ? value : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
              VStack(spacing: 14) {
                if onboarding {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Image("BrandIcon").resizable().frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 20))
                            Text("轻记每一餐").font(.largeTitle.bold())
                            Text("先填写基本资料，了解静息代谢，再开始记录。所有信息可随时修改。")
                                .foregroundStyle(.secondary)
                        }.padding(.vertical, 12)
                    }
                    NavigationLink { ServiceSettingsView(store: store) } label: {
                        Label(session.record == nil ? "登录 NAS 账号" : "管理 NAS 账号", systemImage: "person.crop.circle")
                    }.accessibilityIdentifier("service.open")
                    if session.record != nil {
                        NavigationLink { SyncView() } label: { Label("数据同步", systemImage: "icloud") }
                    }
                }
                Card {
                    HStack {
                        Text("性别")
                        Spacer()
                        PageSegments(selection: $sex, options: BiologicalSex.allCases.map { ($0.label, $0) })
                            .frame(width: 154, height: 34).accessibilityLabel("用于公式的性别")
                    }
                    Divider()
                    field("年龄", text: $age, unit: "岁", decimal: false)
                    Divider()
                    field("身高", text: $height, unit: "cm")
                    Divider()
                    field("体重", text: $weight, unit: "kg")
                    Divider()
                    field("每日摄入目标", text: $target, unit: "kcal")
                }
                if let profile {
                    Card(surface: skin.membershipBackground) {
                        Label("公式代谢估算", systemImage: "sum").font(.subheadline.weight(.semibold))
                        Text("\(Int(profile.formulaKcal.rounded())) kcal/天").font(.title2.bold()).foregroundStyle(skin.accent)
                    }
                }
                Text("代谢公式适用于 18–100 岁。每日摄入目标由你单独设置。")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                if let error { Text(error).foregroundStyle(.red).font(.subheadline) }
              }.padding(Theme.gutter)
            }.background(skin.background).scrollDismissesKeyboard(.interactively)
            .navigationTitle(onboarding ? "欢迎使用轻记" : "编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .pageActions {
                Button(onboarding ? "保存并开始记录" : "保存资料") { save() }
                    .buttonStyle(PrimaryButtonStyle()).disabled(profile == nil || store.storageUnavailable)
                    .accessibilityIdentifier("profile.save")
            }
            .toolbar {
                if !onboarding { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
            }
            .onAppear {
                guard let value = store.snapshot.profile else { return }
                sex = value.sex; age = String(value.age); height = value.heightCM.formatted(.number.grouping(.never))
                weight = value.weightKG.formatted(.number.grouping(.never)); target = value.dailyTarget.formatted(.number.grouping(.never))
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, unit: String, decimal: Bool = true) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, text: text).multilineTextAlignment(.trailing).keyboardType(decimal ? .decimalPad : .numberPad).frame(maxWidth: 110)
            Text(unit).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
        }
    }
    private func save() {
        guard let profile else { return }
        do { try store.saveProfile(profile); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct MetabolismDetailView: View {
    @Environment(\.appSkin) private var skin
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var membership: MembershipModel
    @Environment(\.dismiss) private var dismiss
    @State private var running = false
    @State private var progress = AnalysisProgress(stage: "uploading", message: "正在发送个人资料")
    @State private var started = Date()
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    @State private var consent = false
    @State private var history: [AnalysisProgress] = []
    @State private var cancelled = false
    @State private var showModel = false
    @State private var editProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let profile = store.snapshot.profile {
                        MetabolismCard(profile: profile, assessment: store.snapshot.metabolism)
                        if running {
                            AnalysisStatusView(progress: progress, startedAt: started, history: history) { cancel() }
                        }
                        if cancelled { Label("分析已取消，个人资料已保留。", systemImage: "pause.circle").font(.subheadline).foregroundStyle(.secondary) }
                        if let error {
                            Card {
                                Text(error).foregroundStyle(.secondary).font(.subheadline)
                                Button("检查 AI 模型设置") { showModel = true }.font(.subheadline)
                            }
                        }
                        if let result = store.snapshot.metabolism {
                            Card {
                                Text(result.matches(profile) ? "AI 分析依据" : "上次分析（资料已变化，请重新分析）").font(.headline)
                                Text(result.response.summary).font(.subheadline)
                                ForEach(Array(result.response.assumptions.enumerated()), id: \.offset) { _, value in
                                    Label(value, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                                }
                                Text("分析于 \(result.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Card {
                          DisclosureGroup("公式与综合规则") {
                            Text("Mifflin–St Jeor：\n10 × 体重(kg) + 6.25 × 身高(cm) − 5 × 年龄 + 性别系数\n男性 +5，女性 −161。")
                                .font(.subheadline)
                            Text("综合值采用公式 80% + AI 20%。这是未经临床验证的产品参考规则，不代表更准确的实测结果。AI 可能同样采用已有公式，不是独立测量。")
                                .font(.subheadline)
                            Text("AI 未完成、资料已变化，或 AI 与公式差异超过 20% 时，综合值暂用公式。代谢估算不等于每日摄入目标，也不包含运动。")
                                .font(.caption).foregroundStyle(.secondary)
                            Link("查看公式研究来源", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/2305711/")!)
                          }.font(.subheadline)
                        }
                    }
                }.padding(18)
            }.background(skin.background).navigationTitle("代谢分析").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .pageActions {
                    if !running, store.snapshot.profile != nil {
                        EqualActions {
                            Button("编辑资料") { editProfile = true }.buttonStyle(OutlineButtonStyle())
                            Button(store.snapshot.metabolism == nil ? "AI 分析静息代谢" : "重新分析") { begin() }
                                .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("metabolism.start")
                        }
                    }
                }
                .onDisappear { cancel() }
                .sheet(isPresented: $editProfile) { ProfileEditor(onboarding: false) }
                .sheet(isPresented: $consent) {
                    AIConsentView {
                        do { try store.setAIConsent(true); run() }
                        catch { self.error = error.localizedDescription }
                    }
                }
                .sheet(isPresented: $showModel) {
                    NavigationStack { CustomModelEntry().toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("完成") { showModel = false } }
                    } }
                }
        }
    }
    private func begin() {
        guard store.service.isValid else { error = "请先在“我的 → NAS 账号”登录。"; return }
        if !store.snapshot.aiConsent { consent = true } else { run() }
    }
    private func run() {
        guard !running, let profile = store.snapshot.profile else { return }
        running = true; error = nil; cancelled = false; started = Date()
        progress = .init(stage: "uploading", message: "正在发送个人资料")
        history = [progress]
        task = Task { @MainActor in
            defer { running = false }
            do {
                let response = try await AIClient(configuration: store.service).metabolism(profile: profile) { update in
                    progress = update
                    if history.last?.stage != update.stage { history.append(update) }
                }
                try Task.checkCancellation()
                try store.saveAssessment(response, for: profile)
                Task { await membership.refresh() }
            } catch is CancellationError { cancelled = true } catch { self.error = error.localizedDescription }
        }
    }
    private func cancel() { task?.cancel() }
}

struct SettingsView: View {
    @Environment(\.appSkin) private var skin
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthService
    @EnvironmentObject private var session: AccountSession
    @EnvironmentObject private var membership: MembershipModel
    @State private var editProfile = false
    @State private var metabolism = false
    @State private var showConsent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    VStack(spacing: 4) {
                        BrandWordmark(compact: false)
                        Text(AppBuild.label).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("app.build")
                    }
                    Card {
                        NavigationLink { ServiceSettingsView(store: store) } label: {
                            settingsRow(session.record?.username ?? "NAS 账号", symbol: "person.crop.circle.fill",
                                        detail: membership.status?.active == true ? "会员用户" : "普通用户")
                        }.buttonStyle(.plain)
                    }
                    MembershipCard(active: membership.status?.active == true)
                    Text("AI 模型").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
                    Card {
                        NavigationLink { BuiltInModelView() } label: {
                            settingsRow("内置 DeepSeek", symbol: "fish.fill", detail: quotaLabel, iconColor: .blue)
                        }.accessibilityIdentifier("model.builtin")
                        Divider()
                        NavigationLink { CustomModelEntry() } label: {
                            let member = membership.status?.active == true || membership.status?.enabled == false
                            settingsRow("自定义模型", symbol: "chevron.left.forwardslash.chevron.right",
                                        detail: membership.status?.model == "custom" ? "当前使用" : member ? "" : "会员专享",
                                        locked: !member)
                        }.accessibilityIdentifier("model.open")
                    }.buttonStyle(.plain)
                    Card {
                        NavigationLink { AppearanceView() } label: {
                            settingsRow("外观", symbol: "paintbrush", detail: "")
                        }.accessibilityIdentifier("appearance.open")
                        Divider()
                        NavigationLink { SyncView() } label: {
                            settingsRow("数据同步", symbol: "icloud", detail: store.cloudMessage == "已同步" ? "已同步" : "查看状态")
                        }.accessibilityIdentifier("backup.open")
                        Divider()
                        NavigationLink { HealthSettingsView() } label: {
                            settingsRow("苹果健康", symbol: "heart", detail: health.hasRequested ? "检查权限" : "连接", iconColor: .red)
                        }.accessibilityIdentifier("health.settings")
                    }.buttonStyle(.plain)
                    Card {
                        Button { editProfile = true } label: {
                            settingsRow("个人资料", symbol: "person", detail: "")
                        }
                        Divider()
                        NavigationLink { ServiceSettingsView(store: store) } label: {
                            settingsRow("账号设置", symbol: "gearshape", detail: "")
                        }.accessibilityIdentifier("service.open")
                        if store.snapshot.profile != nil {
                            Divider()
                            Button { metabolism = true } label: {
                                settingsRow("代谢分析", symbol: "waveform.path.ecg", detail: "")
                            }.accessibilityIdentifier("metabolism.open")
                        }
                    }.buttonStyle(.plain)
                    Card {
                        Text("隐私与偏好").font(.headline)
                        if store.snapshot.aiConsent {
                            Toggle("允许主动发起 AI 分析", isOn: Binding(get: { store.snapshot.aiConsent }, set: { value in
                                do { try store.setAIConsent(value) } catch { store.errorMessage = error.localizedDescription }
                            })).font(.subheadline)
                        } else {
                            Button { showConsent = true } label: { settingsRow("启用 AI 分析", symbol: "sparkles", detail: "了解并授权") }
                        }
                        Divider()
                        NavigationLink { PrivacyView() } label: { settingsRow("隐私与使用说明", symbol: "hand.raised", detail: "") }
                    }.buttonStyle(.plain)
                    Text("记录支持离线保存，联网后随账号同步。\n热量与代谢均为估算值，仅供记录参考。")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.vertical, 4)
                }.padding(18)
            }.background(skin.background).navigationTitle("").navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(skin.background, for: .navigationBar)
                .sheet(isPresented: $editProfile) { ProfileEditor(onboarding: false) }
                .sheet(isPresented: $metabolism) { MetabolismDetailView() }
                .sheet(isPresented: $showConsent) {
                    AIConsentView {
                        do { try store.setAIConsent(true) } catch { store.errorMessage = error.localizedDescription }
                    }
                }
        }
    }
    private var quotaLabel: String {
        guard let status = membership.status, status.enabled else { return "" }
        return status.active ? "本期剩余 \(status.remaining) 次" : "体验剩余 \(status.remaining) 次"
    }
    private func settingsRow(_ title: String, symbol: String, detail: String, iconColor: Color? = nil, locked: Bool = false) -> some View {
        HStack(spacing: 11) {
            if title == "内置 DeepSeek" {
                Image("DeepSeekIcon").resizable().scaledToFit().frame(width: 25, height: 25)
            } else {
                Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(iconColor ?? skin.accent).frame(width: 25)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 3)
            if locked { Image(systemName: "lock").font(.caption).foregroundStyle(.secondary) }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }.frame(minHeight: 44).contentShape(Rectangle())
    }
}

struct ServiceSettingsView: View {
    private enum Field: Hashable { case username, password, confirmation }

    @Environment(\.appSkin) private var skin
    @EnvironmentObject private var session: AccountSession
    @FocusState private var focusedField: Field?
    var store: AppStore? = nil
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var working = false
    @State private var registering = true
    @State private var confirmPassword = ""
    @State private var confirmLogout = false
    @State private var confirmImport = false
    @State private var editAddress = false
    @State private var showPassword = false
    @State private var showConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let account = session.record {
                    Card {
                        LabeledContent("当前账号", value: account.username)
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("服务器地址").font(.subheadline.bold())
                            Text(account.baseURL).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        if let store {
                            Divider()
                            LabeledContent("同步状态", value: store.cloudMessage)
                        }
                    }
                    if store?.canImportLegacy == true {
                        Card {
                            Button("导入此手机的旧记录") { confirmImport = true }
                                .frame(minHeight: 44)
                            Text("将本机已有的饮食记录导入当前账号。").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Image("BrandIcon").resizable().frame(width: 74, height: 74)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        Text("欢迎使用轻记").font(.largeTitle.bold()).foregroundStyle(skin.accent)
                        Text(registering ? "创建账号，开始记录每一餐" : "登录账号，继续记录每一餐")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(AppBuild.label).font(.caption2).foregroundStyle(.secondary)
                            .accessibilityIdentifier("app.build")
                    }.padding(.vertical, 12)
                    Card {
                        accountField("用户名") {
                            TextField("请输入用户名", text: $username)
                                .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($focusedField, equals: .username).submitLabel(.next)
                                .onSubmit { focusedField = .password }
                                .accessibilityIdentifier("service.username")
                        }
                        accountPassword("密码", placeholder: "请输入密码", value: $password, visible: $showPassword,
                                        identifier: "service.password", field: .password)
                        if registering {
                            accountPassword("确认密码", placeholder: "请再次输入密码", value: $confirmPassword, visible: $showConfirmation,
                                            identifier: "service.confirm", field: .confirmation)
                        }
                    }
                    Button {
                        focusedField = nil
                        editAddress = true
                    } label: {
                        Card {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("服务器地址").font(.subheadline.bold()).foregroundStyle(.primary)
                                    Text(address).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("service.address.open").disabled(working)
                    if working { ProgressView("正在验证账号…") }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("service.error") }
            }.padding(Theme.gutter)
        }.background(skin.background).scrollDismissesKeyboard(.interactively)
            .navigationTitle(session.record == nil ? "" : "NAS 账号").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedField = nil }.accessibilityIdentifier("service.keyboard.done")
                }
            }
            .pageActions {
                if session.record != nil {
                    Button("退出登录", role: .destructive) { confirmLogout = true }
                        .buttonStyle(OutlineButtonStyle()).accessibilityIdentifier("service.logout")
                } else if focusedField == nil {
                    VStack(spacing: 2) {
                        Button(registering ? "注册并开始" : "登录") { login() }
                            .buttonStyle(PrimaryButtonStyle()).disabled(working || address.isEmpty || username.isEmpty || password.isEmpty || (registering && confirmPassword.isEmpty))
                            .accessibilityIdentifier("service.save")
                        Button(registering ? "已有账号？登录" : "创建新账号") {
                            registering.toggle(); confirmPassword = ""; showPassword = false; showConfirmation = false; error = nil
                        }
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                            .accessibilityIdentifier("service.mode").disabled(working)
                    }
                }
            }
            .sheet(isPresented: $editAddress) {
                ServiceAddressView(address: address) { address = $0 }
                    .presentationDetents([.medium, .large])
            }
            .onAppear { if address.isEmpty { address = session.lastAddress } }
            .alert("退出当前账号？", isPresented: $confirmLogout) {
                Button("退出登录", role: .destructive) {
                    do { try session.signOut() } catch { self.error = error.localizedDescription }
                }
                Button("取消", role: .cancel) {}
            } message: { Text("本机记录会保留在当前账号，重新登录后可以继续使用。") }
            .alert("导入本机旧记录？", isPresented: $confirmImport) {
                Button("导入") {
                    do { try store?.importLegacy() } catch { self.error = error.localizedDescription }
                }
                Button("取消", role: .cancel) {}
            } message: { Text("旧记录会复制到这个账号。") }
    }

    private func accountField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold))
            content().font(.subheadline).padding(.horizontal, 11).frame(minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.25)))
        }
    }

    private func accountPassword(_ title: String, placeholder: String, value: Binding<String>, visible: Binding<Bool>,
                                 identifier: String, field: Field) -> some View {
        let next = field == .password && registering
        return accountField(title) {
            HStack {
                Group {
                    if visible.wrappedValue { TextField(placeholder, text: value) }
                    else { SecureField(placeholder, text: value) }
                }.textContentType(registering ? .oneTimeCode : .password)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focusedField, equals: field).submitLabel(next ? .next : .done)
                    .onSubmit { focusedField = next ? .confirmation : nil }
                    .accessibilityIdentifier(identifier)
                Button { visible.wrappedValue.toggle() } label: {
                    Image(systemName: visible.wrappedValue ? "eye" : "eye.slash").frame(width: 44, height: 44)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel(visible.wrappedValue ? "隐藏\(title)" : "显示\(title)")
            }
        }
    }

    private func login() {
        error = nil
        if registering && password != confirmPassword { error = "两次密码不一致。"; return }
        working = true
        Task {
            defer { working = false }
            do {
                try await session.signIn(address: address, username: username, password: password, registering: registering)
                password = ""
            } catch {
                password = ""
                self.error = error.localizedDescription
            }
        }
    }
}

private struct ServiceAddressView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appSkin) private var skin
    @State private var draft: String
    let save: (String) -> Void

    init(address: String, save: @escaping (String) -> Void) {
        _draft = State(initialValue: address)
        self.save = save
    }

    var body: some View {
        let clean = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        NavigationStack {
            ScrollView {
                Card {
                    Text("服务器地址").font(.subheadline.weight(.semibold))
                    TextField("https://", text: $draft)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .font(.subheadline).padding(.horizontal, 11).frame(minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.25)))
                        .accessibilityIdentifier("service.address")
                }.padding(Theme.gutter)
            }.background(skin.background).navigationTitle("服务器地址").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
                .pageActions {
                    Button("保存地址") { save(clean); dismiss() }
                        .buttonStyle(PrimaryButtonStyle()).disabled(!ServiceConfiguration.validAddress(clean))
                        .accessibilityIdentifier("service.address.save")
                }
        }
    }
}

struct PrivacyView: View {
    @Environment(\.appSkin) private var skin

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                explanation("本机与账号数据", icon: "externaldrive",
                    detail: "本机文件按账号隔离，登录凭证存放在钥匙串。资料、饮食、照片、代谢和活动记录随当前账号同步。")
                explanation("AI 上传", icon: "sparkles",
                    detail: "主动分析时，模型服务收到本次照片和说明，或用于代谢估算的基本资料。请了解所用服务的隐私政策。")
                explanation("估算说明", icon: "scalemass",
                    detail: "照片中的份量与热量、公式及 AI 代谢结果均为估算。保存前请核对食物、份量与热量。")
                Link("DeepSeek 隐私政策", destination: URL(string: "https://cdn.deepseek.com/policies/zh-CN/deepseek-privacy-policy.html")!)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                Link("订阅条款", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.padding(Theme.gutter)
        }.background(skin.background).subpageNavigation(title: "隐私与使用说明")
    }

    private func explanation(_ title: String, icon: String, detail: String) -> some View {
        Card {
            Label(title, systemImage: icon).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
