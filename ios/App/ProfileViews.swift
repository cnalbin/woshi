import SwiftUI

struct ProfileEditor: View {
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
            Form {
                if onboarding {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Image("BrandIcon").resizable().frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 20))
                            Text("轻记每一餐").font(.largeTitle.bold())
                            Text("先填写基本资料，了解静息代谢，再开始记录。所有信息可随时修改。")
                                .foregroundStyle(.secondary)
                        }.padding(.vertical, 12)
                    }.listRowBackground(Color.clear)
                    NavigationLink { ServiceSettingsView(store: store) } label: {
                        Label(session.record == nil ? "登录 NAS 账号" : "管理 NAS 账号", systemImage: "person.crop.circle")
                    }.accessibilityIdentifier("service.open")
                    if session.record != nil {
                        NavigationLink { SyncView() } label: { Label("数据同步", systemImage: "icloud") }
                    }
                }
                Section {
                    Picker("用于公式的性别", selection: $sex) { ForEach(BiologicalSex.allCases) { Text($0.label).tag($0) } }
                    field("年龄", text: $age, unit: "岁", decimal: false)
                    field("身高", text: $height, unit: "cm")
                    field("体重", text: $weight, unit: "kg")
                } header: { Text("个人资料") } footer: { Text("本版代谢分析面向 18–100 岁成年用户。公式不包含活动消耗，无法代替实测代谢。") }
                Section {
                    field("每日摄入目标", text: $target, unit: "kcal")
                } footer: { Text("请填写自己的摄入目标。此项独立于代谢估算，默认值仅用于初始化，不是个性化饮食建议。") }
                if let profile {
                    Section("公式预览") {
                        LabeledContent("静息代谢估算", value: "\(Int(profile.formulaKcal.rounded())) kcal/天")
                    }
                }
                if let error { Text(error).foregroundStyle(.red).font(.subheadline) }
            }
            .navigationTitle(onboarding ? "欢迎使用轻记" : "编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(onboarding ? "保存并开始记录" : "保存资料") { save() }
                    .buttonStyle(PrimaryButtonStyle()).disabled(profile == nil || store.storageUnavailable)
                    .accessibilityIdentifier("profile.save")
                    .padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let profile = store.snapshot.profile {
                        MetabolismCard(profile: profile, assessment: store.snapshot.metabolism) {}
                        if running {
                            AnalysisStatusView(progress: progress, startedAt: started, history: history) { cancel() }
                        } else {
                            Button { begin() } label: { Label("AI 分析静息代谢", systemImage: "sparkles") }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("metabolism.start")
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
                .onDisappear { cancel() }
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
                        Button { Task { await health.connect() } } label: {
                            settingsRow("苹果健康", symbol: "heart", detail: health.hasRequested ? "检查权限" : "连接", iconColor: .red)
                        }
                    }.buttonStyle(.plain)
                    Card {
                        HStack {
                            Text("个人资料").font(.headline)
                            Spacer()
                            Button(store.snapshot.profile == nil ? "完善资料" : "编辑") { editProfile = true }.font(.caption.weight(.semibold))
                        }
                        if let profile = store.snapshot.profile {
                            HStack {
                                profileMetric("性别", profile.sex.label)
                                profileMetric("年龄", "\(profile.age) 岁")
                                profileMetric("身高", "\(Int(profile.heightCM)) cm")
                                profileMetric("体重", "\(profile.weightKG.formatted(.number.precision(.fractionLength(0...1)))) kg")
                            }
                            Divider()
                            HStack {
                                Label("每日摄入目标", systemImage: "scope").font(.subheadline)
                                Spacer()
                                Text("\(Int(profile.dailyTarget)) kcal").font(.subheadline.weight(.semibold)).foregroundStyle(skin.accent)
                            }
                        } else {
                            Text("填写基本信息，查看公式、AI 与综合代谢估算。").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let profile = store.snapshot.profile {
                        MetabolismCard(profile: profile, assessment: store.snapshot.metabolism) { metabolism = true }
                        Button { metabolism = true } label: {
                            Label("查看代谢分析与估算依据", systemImage: "sparkles").font(.subheadline.weight(.medium))
                        }.accessibilityIdentifier("metabolism.open")
                    }
                    Card {
                        NavigationLink { ServiceSettingsView(store: store) } label: {
                            settingsRow("NAS 账号", symbol: "person.crop.circle", detail: session.record?.username ?? "登录")
                        }.accessibilityIdentifier("service.open")
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
    private func profileMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
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
        }.frame(minHeight: 32).contentShape(Rectangle())
    }
}

struct ServiceSettingsView: View {
    @EnvironmentObject private var session: AccountSession
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

    var body: some View {
        Form {
            if let account = session.record {
                Section("当前账号") {
                    LabeledContent("用户名", value: account.username)
                    LabeledContent("NAS 地址", value: account.baseURL)
                    Button("退出登录", role: .destructive) { confirmLogout = true }
                        .accessibilityIdentifier("service.logout")
                }
                if store?.canImportLegacy == true {
                    Section {
                        Button("导入此手机的旧记录") { confirmImport = true }
                    } footer: { Text("如果旧记录只存在这部手机，可将资料、饮食和照片复制到当前账号，再自动同步到服务器。") }
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image("BrandIcon").resizable().frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        Text("欢迎使用轻记").font(.largeTitle.bold())
                        Text("创建账号，开始记录每一餐").foregroundStyle(.secondary)
                        Text(AppBuild.label).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("app.build")
                    }.padding(.vertical, 8)
                }.listRowBackground(Color.clear)
                Section {
                    TextField("https://api.example.com", text: $address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .accessibilityIdentifier("service.address")
                    TextField("用户名", text: $username)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("service.username")
                    // Registration uses manual secure entry to avoid the system's strong-password
                    // overlay swallowing edits in paired SwiftUI SecureFields. Login keeps AutoFill.
                    SecureField("密码", text: $password).textContentType(registering ? .oneTimeCode : .password)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("service.password")
                    if registering {
                        SecureField("确认密码", text: $confirmPassword).textContentType(.oneTimeCode)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("service.confirm")
                    }
                } header: { Text(registering ? "创建轻记账号" : "登录轻记账号") } footer: {
                    Text("用户名支持字母、数字、点、横线及下划线。注册密码至少12个字符，记录随账号自动同步。")
                }
                Section {
                    Button(registering ? "注册并开始" : "登录") { login() }.disabled(working || address.isEmpty || username.isEmpty || password.isEmpty)
                        .accessibilityIdentifier("service.save")
                    Button(registering ? "已有账号？登录" : "创建新账号") { registering.toggle() }
                        .accessibilityIdentifier("service.mode")
                    if working { ProgressView("正在验证账号…") }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("service.error") }
        }.navigationTitle("NAS 账号").navigationBarTitleDisplayMode(.inline)
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

struct PrivacyView: View {
    var body: some View {
        List {
            Section("本机数据") {
                Text("本机文件按账号隔离，登录凭证保存在钥匙串。个人资料、饮食、照片、代谢结果和活动汇总随当前账号自动同步到所连接的服务器。")
            }
            Section("AI 上传") {
                Text("只有主动发起 AI 分析时，所配置的模型服务才收到本餐照片与补充说明，或年龄、性别、身高、体重。AI 分析需要单独授权。请了解所选服务的隐私政策。")
                Link("DeepSeek 隐私政策", destination: URL(string: "https://cdn.deepseek.com/policies/zh-CN/deepseek-privacy-policy.html")!)
            }
            Section("估算边界") {
                Text("单张照片无法可靠测量实际克数、油、糖和内部配料。公式与 AI 都不是代谢实测。综合规则未经临床验证，不用于疾病诊断、治疗或自动处方。")
            }
        }.navigationTitle("隐私与使用说明")
    }
}
