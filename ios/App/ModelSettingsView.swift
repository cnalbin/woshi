import SwiftUI

struct ModelSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var address = "https://api.deepseek.com"
    @State private var textModel = ""
    @State private var visionModel = ""
    @State private var key = ""
    @State private var hasKey = false
    @State private var busy = false
    @State private var message = ""
    private struct Configuration: Codable {
        var baseURL: String
        var textModel: String
        var visionModel: String
        var hasKey: Bool
    }
    var body: some View {
        Form {
            Section("当前账号的 AI 服务") {
                TextField("API 地址", text: $address)
                SecureField(hasKey ? "已保存，留空保留原 Key" : "API Key", text: $key)
                TextField("文字分析模型", text: $textModel)
                TextField("照片识别模型", text: $visionModel)
            }.textInputAutocapitalization(.never).autocorrectionDisabled()
            Section {
                Button("测试连接") { perform(test: true) }.disabled(busy)
                Button("保存配置") { perform(test: false) }.disabled(busy)
                if busy { ProgressView("正在连接 AI 服务…") }
                if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
            } footer: {
                Text("照片识别需要支持图片的模型。Key 加密保存在服务器，仅用于当前账号。测试连接会先保存配置并调用文字模型，可能产生少量费用。")
            }
        }.navigationTitle("AI 模型设置")
            .task {
                do {
                    let data = try await CloudClient(configuration: store.service).request("v1/ai/settings", method: "GET")
                    let value = try JSONDecoder().decode(Configuration.self, from: data)
                    address = value.baseURL; textModel = value.textModel; visionModel = value.visionModel; hasKey = value.hasKey
                } catch { message = error.localizedDescription }
            }
    }
    private func perform(test: Bool) {
        struct Input: Encodable { var baseURL: String; var textModel: String; var visionModel: String; var apiKey: String }
        busy = true; message = ""
        Task {
            defer { busy = false }
            do {
                let client = CloudClient(configuration: store.service)
                let data = try JSONEncoder().encode(Input(baseURL: address, textModel: textModel, visionModel: visionModel, apiKey: key))
                _ = try await client.request("v1/ai/settings", method: "PUT", data: data)
                hasKey = hasKey || !key.isEmpty; key = ""
                message = "已保存"
                if test {
                    struct Result: Decodable { var message: String }
                    let result = try await client.request("v1/ai/test", method: "POST")
                    message = try JSONDecoder().decode(Result.self, from: result).message
                }
            } catch { message = error.localizedDescription }
        }
    }
}
