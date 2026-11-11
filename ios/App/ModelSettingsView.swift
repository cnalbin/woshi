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
    @EnvironmentObject private var membership: MembershipModel
    @Environment(\.appSkin) private var skin
    @State private var draft = AIConfigurationDraft()
    @State private var hasKey = false
    @State private var savedAddress = ""
    @State private var defaultMeal = ""
    @State private var defaultMetabolism = ""
    @State private var loading = false
    @State private var loaded = false
    @State private var saving = false
    @State private var message: String?
    @State private var showKey = false

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

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("自定义模型").font(.title.bold()).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                if membership.status?.model == "custom" {
                    HStack {
                        Label("自定义模型已启用", systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("切回内置模型") { Task { await switchToBuiltIn() } }
                            .font(.caption.weight(.semibold)).disabled(saving)
                    }.padding(14).foregroundStyle(skin.accent)
                        .background(skin.softAccent, in: RoundedRectangle(cornerRadius: 14))
                }
                if loading { ProgressView("正在读取模型设置…") }
                Card {
                    field("API 地址") {
                        TextField("https://api.deepseek.com", text: $draft.baseURL).keyboardType(.URL)
                    }
                    field("API Key") {
                        HStack {
                            if showKey {
                                TextField(keyPlaceholder, text: $draft.apiKey)
                            } else {
                                SecureField(keyPlaceholder, text: $draft.apiKey)
                            }
                            Button { showKey.toggle() } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye").foregroundStyle(.secondary)
                            }.accessibilityLabel(showKey ? "隐藏正在输入的 API Key" : "显示正在输入的 API Key")
                        }
                    }
                    field("文字模型") { TextField("文字分析模型", text: $draft.textModel) }
                    field("图片模型") { TextField("照片识别模型", text: $draft.visionModel) }
                }.textInputAutocapitalization(.never).autocorrectionDisabled().disabled(!loaded || saving)
                if loaded {
                    Card {
                        NavigationLink {
                            PromptEditor(meal: $draft.mealPrompt, metabolism: $draft.metabolismPrompt,
                                         defaultMeal: defaultMeal, defaultMetabolism: defaultMetabolism, service: store.service)
                        } label: { row("编辑提示词", symbol: "pencil") }
                        Divider()
                        NavigationLink {
                            ModelDebugView(configuration: draft, service: store.service)
                        } label: { row("调试模型", symbol: "terminal") }
                            .accessibilityIdentifier("model.debug")
                        Divider()
                        NavigationLink {
                            ModelBalanceView(configuration: draft, service: store.service)
                        } label: { row("查询余额", symbol: "creditcard") }
                            .accessibilityIdentifier("model.balance")
                    }.buttonStyle(.plain)
                    Label("自定义调用由服务商计费", systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
                }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }
                if !loaded && !loading { Button("重新读取设置") { Task { await load() } } }
            }.padding(18)
        }.background(skin.background).brandedNavigation(title: "自定义模型")
            .task { if !loaded { await load() } }
            .safeAreaInset(edge: .bottom) {
                if loaded {
                    Button(saving ? "正在保存…" : "保存并启用") { Task { await save() } }
                        .buttonStyle(PrimaryButtonStyle()).disabled(saving || !valid)
                        .accessibilityIdentifier("model.save")
                        .padding(.horizontal, 18).padding(.vertical, 10).background(skin.background)
                }
            }
    }

    private var valid: Bool {
        !draft.textModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.visionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!draft.apiKey.isEmpty || (hasKey && sameAddress))
    }

    private var keyPlaceholder: String { hasKey && sameAddress ? "•••••••• · 已保存" : "输入个人 API Key" }

    private var sameAddress: Bool {
        draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")) == savedAddress
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.medium))
            content().font(.subheadline).padding(10)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.23)))
        }
    }

    private func row(_ title: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.font(.subheadline).frame(minHeight: 30).contentShape(Rectangle())
    }

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
        loading = true; message = nil
        defer { loading = false }
        do {
            let data = try await CloudClient(configuration: store.service).request("v1/ai/settings", method: "GET")
            apply(try JSONDecoder().decode(Configuration.self, from: data))
        } catch { message = error.localizedDescription }
    }

    private func save() async {
        guard !saving else { return }
        saving = true; message = nil
        defer { saving = false }
        do {
            let data = try JSONEncoder().encode(draft)
            let response = try await CloudClient(configuration: store.service).request("v1/ai/settings", method: "PUT", data: data)
            apply(try JSONDecoder().decode(Configuration.self, from: response))
            if membership.status?.enabled == true { try await membership.update(model: "custom") }
            message = "自定义模型已启用"
        } catch { message = error.localizedDescription }
    }

    private func switchToBuiltIn() async {
        guard !saving else { return }
        saving = true; message = nil
        defer { saving = false }
        do { try await membership.update(model: "builtIn") }
        catch { message = error.localizedDescription }
    }
}

private struct PromptEditor: View {
    @Environment(\.appSkin) private var skin
    @Environment(\.dismiss) private var dismiss
    @Binding var meal: String
    @Binding var metabolism: String
    let defaultMeal: String
    let defaultMetabolism: String
    let service: ServiceConfiguration
    @State private var mode = 0
    @State private var mealText = ""
    @State private var metabolismText = ""
    @State private var saving = false
    @State private var message: String?

    private var selectedText: Binding<String> { mode == 0 ? $mealText : $metabolismText }
    var body: some View {
        VStack(spacing: 16) {
            Text("编辑提示词").font(.title.bold()).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Picker("提示词类型", selection: $mode) {
                Text("拍照识别").tag(0)
                Text("静息代谢").tag(1)
            }.pickerStyle(.segmented)
            TextEditor(text: selectedText).font(.body).padding(8)
                .scrollContentBackground(.hidden).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("提示词")
            Text(message ?? "结果格式由轻记统一校验").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("恢复默认") { selectedText.wrappedValue = mode == 0 ? defaultMeal : defaultMetabolism }
                    .buttonStyle(.bordered)
                Button(saving ? "正在保存…" : "保存提示词") { Task { await save() } }.buttonStyle(PrimaryButtonStyle())
            }.disabled(saving)
        }.padding(18).background(skin.background).brandedNavigation(title: "编辑提示词")
            .task {
                mealText = meal.isEmpty ? defaultMeal : meal
                metabolismText = metabolism.isEmpty ? defaultMetabolism : metabolism
            }
    }

    private func save() async {
        struct Prompts: Encodable { let mealPrompt: String; let metabolismPrompt: String }
        guard mealText.count <= 6000 && metabolismText.count <= 6000 else {
            message = "每条提示词最多 6000 字。"
            return
        }
        saving = true; message = nil
        defer { saving = false }
        let mealValue = mealText == defaultMeal ? "" : mealText
        let metabolismValue = metabolismText == defaultMetabolism ? "" : metabolismText
        do {
            let data = try JSONEncoder().encode(Prompts(mealPrompt: mealValue, metabolismPrompt: metabolismValue))
            _ = try await CloudClient(configuration: service).request("v1/ai/prompts", method: "PUT", data: data)
            meal = mealValue; metabolism = metabolismValue
            dismiss()
        } catch { message = error.localizedDescription }
    }
}

private struct ModelBalanceView: View {
    @Environment(\.appSkin) private var skin
    let configuration: AIConfigurationDraft
    let service: ServiceConfiguration
    @State private var checking = false
    @State private var response: Balance?
    @State private var message: String?
    @State private var checkedAt: Date?

    private struct Balance: Decodable {
        struct Amount: Decodable, Identifiable {
            let currency: String
            let total_balance: String
            let granted_balance: String
            let topped_up_balance: String
            var id: String { currency }
            var symbol: String { currency == "CNY" ? "¥" : currency == "USD" ? "$" : currency + " " }
        }
        let supported: Bool
        let message: String?
        let balance_infos: [Amount]?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("查询余额").font(.title.bold()).accessibilityAddTraits(.isHeader)
                Card {
                    HStack(spacing: 12) {
                        Image(systemName: "fish.fill").font(.title2).foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(URLComponents(string: configuration.baseURL)?.host == "api.deepseek.com" ? "DeepSeek" : "模型服务商").font(.headline)
                            Text("个人 API 账号").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(response?.balance_infos ?? []) { amount in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("总余额").font(.headline)
                        Text(amount.symbol + amount.total_balance).font(.system(size: 38, weight: .bold, design: .rounded))
                            .monospacedDigit().foregroundStyle(skin.accent)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        .background(skin.softAccent, in: RoundedRectangle(cornerRadius: 16))
                    Card {
                        LabeledContent("充值余额", value: amount.symbol + amount.topped_up_balance)
                        Divider()
                        LabeledContent("赠金余额", value: amount.symbol + amount.granted_balance)
                    }
                }
                if let checkedAt { Text("更新于 \(checkedAt.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                Button { Task { await refresh() } } label: {
                    Label(checking ? "正在查询…" : "刷新余额", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }.buttonStyle(.bordered).disabled(checking)
            }.padding(18)
        }.background(skin.background).brandedNavigation(title: "查询余额")
            .task { await refresh() }
    }

    private func refresh() async {
        guard !checking else { return }
        checking = true; message = nil
        defer { checking = false }
        do {
            let body = try JSONEncoder().encode(configuration)
            let data = try await CloudClient(configuration: service).request("v1/ai/balance", method: "POST", data: body)
            let result = try JSONDecoder().decode(Balance.self, from: data)
            response = result
            checkedAt = result.supported ? Date() : nil
            message = result.message ?? (result.balance_infos?.isEmpty == true ? "服务商未返回余额明细。" : nil)
        } catch { message = error.localizedDescription }
    }
}
