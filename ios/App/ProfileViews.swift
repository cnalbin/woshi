import SwiftUI

struct ProfileEditor: View {
    @EnvironmentObject private var store: AppStore
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
                    NavigationLink { BackupView() } label: { Label("从旧手机的 NAS 备份恢复", systemImage: "arrow.down.circle") }
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
        guard ServiceConfiguration.current.isValid else { error = "请先在“我的 → AI 服务设置”配置服务。"; return }
        if !store.snapshot.aiConsent { consent = true } else { run() }
    }
    private func run() {
        guard !running, let profile = store.snapshot.profile else { return }
        running = true; error = nil; started = Date()
        progress = .init(stage: "uploading", message: "正在发送个人资料")
        task = Task { @MainActor in
            defer { running = false }
            do {
                let response = try await AIClient(configuration: .current).metabolism(profile: profile) { progress = $0 }
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
                    NavigationLink { ServiceSettingsView() } label: { Label("AI 服务设置", systemImage: "network") }
                        .accessibilityIdentifier("service.open")
                    NavigationLink { BackupView() } label: { Label("NAS 备份与恢复", systemImage: "externaldrive") }
                        .accessibilityIdentifier("backup.open")
                    Button { Task { await health.connect() } } label: {
                        HStack { Label("苹果健康", systemImage: "heart"); Spacer(); Text(health.hasRequested ? "检查连接" : "连接").foregroundStyle(.secondary) }
                    }
                    Text("读取每日活动能量。开启 NAS 备份后保存每日汇总，AI 分析不会收到运动数据。")
                        .font(.caption).foregroundStyle(.secondary)
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
                    Text("本机支持离线记录。启用 NAS 备份后，可以在换机时恢复。")
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
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var token = ""
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                TextField("https://api.example.com", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).accessibilityIdentifier("service.address")
                SecureField("后端访问令牌", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("service.token")
            } header: { Text("你的轻记后端") } footer: { Text("此处填写轻记后端地址和 APP_ACCESS_TOKEN，不能直接填写 DeepSeek 地址或 DeepSeek API Key。服务令牌安全保存在设备钥匙串。") }
            Section {
                Button("保存配置") {
                    let clean = address.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard ServiceConfiguration(baseURL: clean, token: cleanToken).isValid else {
                        error = "请填写有效的 HTTPS 服务地址和令牌。"; return
                    }
                    do {
                        try KeychainToken.save(cleanToken)
                        UserDefaults.standard.set(clean, forKey: "serviceURL")
                        store.serviceConfigurationChanged()
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("service.save")
                if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("service.error") }
            }
            Section { Text("后端配置完成前，个人资料、公式计算和手动记录仍可正常使用。首次分析前会说明上传内容。") }
        }.navigationTitle("AI 服务设置").navigationBarTitleDisplayMode(.inline)
            .onAppear { let config = ServiceConfiguration.current; address = config.baseURL; token = config.token }
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("本机数据") {
                Text("本机文件启用文件保护，服务令牌保存在钥匙串。你可以选择把个人资料、饮食、照片、代谢结果和活动汇总保存到自己的 NAS。")
            }
            Section("AI 上传") {
                Text("只有主动发起 AI 分析时，DeepSeek 才收到本餐照片与补充说明，或年龄、性别、身高、体重。NAS 备份与 AI 分析分别授权。DeepSeek 的处理方式以其政策为准。")
                Link("DeepSeek 隐私政策", destination: URL(string: "https://cdn.deepseek.com/policies/zh-CN/deepseek-privacy-policy.html")!)
            }
            Section("估算边界") {
                Text("单张照片无法可靠测量实际克数、油、糖和内部配料。公式与 AI 都不是代谢实测。综合规则未经临床验证，不用于疾病诊断、治疗或自动处方。")
            }
        }.navigationTitle("隐私与使用说明")
    }
}
