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
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var running = false
    @State private var progress = AnalysisProgress(stage: "uploading", message: "正在发送个人资料")
    @State private var started = Date()
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    @State private var consent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let profile = store.snapshot.profile {
                        MetabolismCard(profile: profile, assessment: store.snapshot.metabolism) {}
                        if running {
                            AnalysisStatusView(progress: progress, startedAt: started) { cancel() }
                        } else {
                            Button { begin() } label: { Label("AI 分析静息代谢", systemImage: "sparkles") }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("metabolism.start")
                        }
                        if let error { Text(error).foregroundStyle(.red).font(.subheadline) }
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
                            Text("公式与综合规则").font(.headline)
                            Text("Mifflin–St Jeor：\n10 × 体重(kg) + 6.25 × 身高(cm) − 5 × 年龄 + 性别系数\n男性 +5，女性 −161。")
                                .font(.subheadline)
                            Text("综合值采用公式 80% + AI 20%。这是未经临床验证的产品参考规则，不代表更准确的实测结果。AI 可能同样采用已有公式，不是独立测量。")
                                .font(.subheadline)
                            Text("AI 未完成、资料已变化，或 AI 与公式差异超过 20% 时，综合值暂用公式。代谢估算不等于每日摄入目标，也不包含运动。")
                                .font(.caption).foregroundStyle(.secondary)
                            Link("查看公式研究来源", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/2305711/")!)
                        }
                    }
                }.padding(18)
            }.background(Theme.background).navigationTitle("代谢分析").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .onDisappear { cancel() }
                .sheet(isPresented: $consent) {
                    AIConsentView {
                        do { try store.setAIConsent(true); run() }
                        catch { self.error = error.localizedDescription }
                    }
                }
        }
    }
    private func begin() {
        guard store.service.isValid else { error = "请先在“我的 → NAS 账号”登录。"; return }
        if !store.snapshot.aiConsent { consent = true } else { run() }
    }
    private func run() {
        guard !running, let profile = store.snapshot.profile else { return }
        running = true; error = nil; started = Date()
        progress = .init(stage: "uploading", message: "正在发送个人资料")
        task = Task { @MainActor in
            defer { running = false }
            do {
                let response = try await AIClient(configuration: store.service).metabolism(profile: profile) { progress = $0 }
                try Task.checkCancellation()
                try store.saveAssessment(response, for: profile)
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    private func cancel() { task?.cancel() }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthService
    @EnvironmentObject private var session: AccountSession
    @State private var editProfile = false
    @State private var metabolism = false
    @State private var showConsent = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image("BrandIcon").resizable().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 17))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("轻记").font(.title2.bold())
                            Text("记下每一餐，看见每一天").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }
                if let profile = store.snapshot.profile {
                    Section("个人信息") {
                        LabeledContent("性别", value: profile.sex.label)
                        LabeledContent("年龄", value: "\(profile.age) 岁")
                        LabeledContent("身高", value: "\(profile.heightCM.formatted()) cm")
                        LabeledContent("体重", value: "\(profile.weightKG.formatted()) kg")
                        LabeledContent("每日摄入目标", value: "\(Int(profile.dailyTarget)) kcal")
                        Button("编辑资料") { editProfile = true }
                    }
                    Section {
                        Button { metabolism = true } label: { Label("查看三种代谢结果与 AI 分析", systemImage: "sparkles") }
                            .accessibilityIdentifier("metabolism.open")
                    }
                }
                Section("连接") {
                    NavigationLink { ModelSettingsView() } label: { Label("AI 模型设置", systemImage: "sparkles") }
                        .accessibilityIdentifier("model.open")
                    Text(store.cloudMessage).font(.caption).foregroundStyle(.secondary)
                    NavigationLink { ServiceSettingsView(store: store) } label: {
                        Label(session.record.map { "NAS 账号 · \($0.username)" } ?? "登录 NAS 账号", systemImage: "person.crop.circle")
                    }
                        .accessibilityIdentifier("service.open")
                    NavigationLink { SyncView() } label: { Label("数据同步", systemImage: "icloud") }
                        .accessibilityIdentifier("backup.open")
                    Button { Task { await health.connect() } } label: {
                        HStack { Label("苹果健康", systemImage: "heart"); Spacer(); Text(health.hasRequested ? "检查连接" : "连接").foregroundStyle(.secondary) }
                    }
                    Text("读取每日活动能量，每日汇总随当前账号自动同步。AI 分析不会收到运动数据。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if store.snapshot.profile == nil {
                    Section { Button("完善个人资料") { editProfile = true } }
                }
                Section("隐私与数据") {
                    if store.snapshot.aiConsent {
                        Toggle("允许主动发起 AI 分析", isOn: Binding(get: { store.snapshot.aiConsent }, set: { value in
                            do { try store.setAIConsent(value) } catch { store.errorMessage = error.localizedDescription }
                        }))
                    } else {
                        Button("了解并启用 AI 分析") { showConsent = true }
                    }
                    NavigationLink("隐私与使用说明") { PrivacyView() }
                    Text("本机支持离线记录，联网后自动同步。换机登录同一服务器的相同账号，即可同步已有记录。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section { Text("轻记 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · 热量与代谢为估算值").font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle("我的")
            .sheet(isPresented: $editProfile) { ProfileEditor(onboarding: false) }
            .sheet(isPresented: $metabolism) { MetabolismDetailView() }
            .sheet(isPresented: $showConsent) {
                AIConsentView {
                    do { try store.setAIConsent(true) } catch { store.errorMessage = error.localizedDescription }
                }
            }
        }
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
                    Image("BrandIcon").resizable().frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Text("欢迎使用轻记").font(.largeTitle.bold())
                    Text("创建账号，开始记录每一餐").foregroundStyle(.secondary)
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
