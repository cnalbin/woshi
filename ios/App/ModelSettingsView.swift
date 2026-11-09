import SwiftUI

struct AIConfigurationDraft: Encodable {
    var baseURL = "https://api.deepseek.com"
    var textModel = ""
    var visionModel = ""
    var apiKey = ""
    var mealPrompt = ""
    var metabolismPrompt = ""
}

struct ModelSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = AIConfigurationDraft()
    @State private var hasKey = false
    @State private var savedAddress = ""
    @State private var defaultMeal = ""
    @State private var defaultMetabolism = ""
    @State private var loading = true
    @State private var loaded = false
    @State private var saving = false
    @State private var checkingBalance = false
    @State private var settingsMessage = ""
    @State private var balanceMessage = ""
    @State private var balance: BalanceResponse?

    private struct Configuration: Decodable {
        let baseURL: String
        let textModel: String
        let visionModel: String
        let hasKey: Bool
        let mealPrompt: String?
        let metabolismPrompt: String?
        let defaultMealPrompt: String?
        let defaultMetabolismPrompt: String?
    }

    private struct BalanceResponse: Decodable {
        struct Amount: Decodable, Identifiable {
            let currency: String
            let total_balance: String
            let granted_balance: String
            let topped_up_balance: String
            var id: String { currency }
        }
        let supported: Bool
        let message: String?
        let is_available: Bool?
        let balance_infos: [Amount]?
    }

    var body: some View {
        Form {
            if loading { ProgressView("正在读取模型设置…") }
            Section("当前账号的 AI 服务") {
                TextField("API 地址", text: $draft.baseURL).keyboardType(.URL)
                SecureField(hasKey && sameAddress ? "已保存，留空保留原 Key" : "API Key", text: $draft.apiKey)
                TextField("文字分析模型", text: $draft.textModel)
                TextField("照片识别模型", text: $draft.visionModel)
            }.textInputAutocapitalization(.never).autocorrectionDisabled().disabled(!loaded || saving)
            if loaded {
                Section {
                    NavigationLink {
                        PromptEditor(title: "拍照识别提示词", prompt: $draft.mealPrompt, defaultPrompt: defaultMeal)
                    } label: {
                        LabeledContent("拍照识别", value: draft.mealPrompt.isEmpty ? "默认" : "自定义")
                    }
                    NavigationLink {
                        PromptEditor(title: "静息代谢提示词", prompt: $draft.metabolismPrompt, defaultPrompt: defaultMetabolism)
                    } label: {
                        LabeledContent("静息代谢", value: draft.metabolismPrompt.isEmpty ? "默认" : "自定义")
                    }
                } header: { Text("提示词") } footer: {
                    Text("提示词按账号保存。正式分析会保留 App 所需的 JSON 字段和单位。")
                }.disabled(saving)
                Section {
                    NavigationLink {
                        ModelDebugView(configuration: draft, service: store.service)
                    } label: { Label("调试模型", systemImage: "terminal") }
                        .accessibilityIdentifier("model.debug")
                    Button("保存配置") { Task { await save() } }.disabled(saving)
                    if saving { ProgressView("正在保存…") }
                } footer: {
                    Text("调试使用当前填写的地址、模型、Key 和提示词草稿。模型调用可能产生费用。")
                }
                Section("API 账号余额") {
                    if let balance, balance.supported {
                        if let available = balance.is_available {
                            Label(available ? "余额可用" : "余额不足", systemImage: available ? "checkmark.circle" : "exclamationmark.circle")
                                .foregroundStyle(available ? Theme.green : Theme.orange)
                        }
                        ForEach(balance.balance_infos ?? []) { amount in
                            VStack(alignment: .leading, spacing: 6) {
                                LabeledContent("总余额 · \(amount.currency)", value: amount.total_balance).font(.headline)
                                LabeledContent("充值余额", value: amount.topped_up_balance)
                                LabeledContent("赠金余额", value: amount.granted_balance)
                            }.font(.subheadline).monospacedDigit()
                        }
                        if balance.balance_infos?.isEmpty != false {
                            Text("服务商未返回余额明细").foregroundStyle(.secondary)
                        }
                    }
                    Button("刷新余额") { Task { await checkBalance() } }
                        .disabled(checkingBalance || saving).accessibilityIdentifier("model.balance")
                    if checkingBalance { ProgressView("正在查询余额…") }
                    if !balanceMessage.isEmpty { Text(balanceMessage).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            if !settingsMessage.isEmpty { Text(settingsMessage).font(.footnote).textSelection(.enabled) }
            if !loaded && !loading { Button("重新读取设置") { Task { await load() } } }
        }.scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("AI 模型设置").navigationBarTitleDisplayMode(.inline)
            .task { if !loaded { await load() } }
            .onChange(of: draft.baseURL) { _, _ in clearBalance() }
            .onChange(of: draft.apiKey) { _, _ in clearBalance() }
    }

    private var sameAddress: Bool {
        draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")) == savedAddress
    }

    private func clearBalance() { balance = nil; balanceMessage = "" }

    private func apply(_ configuration: Configuration) {
        draft.baseURL = configuration.baseURL
        draft.textModel = configuration.textModel
        draft.visionModel = configuration.visionModel
        draft.apiKey = ""
        draft.mealPrompt = configuration.mealPrompt ?? ""
        draft.metabolismPrompt = configuration.metabolismPrompt ?? ""
        savedAddress = configuration.baseURL
        defaultMeal = configuration.defaultMealPrompt ?? ""
        defaultMetabolism = configuration.defaultMetabolismPrompt ?? ""
        hasKey = configuration.hasKey
        loaded = true
    }

    private func load() async {
        loading = true; settingsMessage = ""
        defer { loading = false }
        do {
            let data = try await CloudClient(configuration: store.service).request("v1/ai/settings", method: "GET")
            apply(try JSONDecoder().decode(Configuration.self, from: data))
        } catch { settingsMessage = error.localizedDescription }
    }

    private func save() async {
        guard !saving else { return }
        saving = true; settingsMessage = ""
        defer { saving = false }
        do {
            let data = try JSONEncoder().encode(draft)
            let response = try await CloudClient(configuration: store.service).request("v1/ai/settings", method: "PUT", data: data)
            apply(try JSONDecoder().decode(Configuration.self, from: response))
            settingsMessage = "已保存"
        } catch { settingsMessage = error.localizedDescription }
    }

    private func checkBalance() async {
        guard !checkingBalance else { return }
        let request = draft
        checkingBalance = true; clearBalance()
        defer { checkingBalance = false }
        do {
            let data = try JSONEncoder().encode(request)
            let response = try await CloudClient(configuration: store.service).request("v1/ai/balance", method: "POST", data: data)
            guard request.baseURL == draft.baseURL, request.apiKey == draft.apiKey else { return }
            balance = try JSONDecoder().decode(BalanceResponse.self, from: response)
            balanceMessage = balance?.message ?? ""
        } catch {
            if request.baseURL == draft.baseURL, request.apiKey == draft.apiKey { balanceMessage = error.localizedDescription }
        }
    }
}

private struct PromptEditor: View {
    let title: String
    @Binding var prompt: String
    let defaultPrompt: String

    @State private var text = ""

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text).font(.body).frame(minHeight: 280)
                    .accessibilityLabel(title)
                    .onChange(of: text) { _, value in
                        let limited = String(value.prefix(6000))
                        if limited != value { text = limited }
                        prompt = limited == defaultPrompt ? "" : limited
                    }
            } footer: { Text("返回后点「保存配置」生效。清空提示词会使用默认内容。") }
            Button("恢复默认") { prompt = ""; text = defaultPrompt }.disabled(text == defaultPrompt)
        }.scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .onAppear { text = prompt.isEmpty ? defaultPrompt : prompt }
    }
}
