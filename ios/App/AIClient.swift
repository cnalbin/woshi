import Foundation
import Security

enum KeychainToken {
    private static let service = "com.cnalbin.qingji.api"
    private static let account = "nas-session"
    static func load() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ token: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        if token.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AIError.message("无法清除访问令牌。") }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let addStatus = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AIError.message("无法安全保存访问令牌（\(addStatus)）。请确认应用签名与钥匙串权限。")
            }
        } else if status != errSecSuccess { throw AIError.message("无法安全保存访问令牌（\(status)）。请确认应用签名与钥匙串权限。") }
    }
}

struct ServiceConfiguration {
    var baseURL: String
    var token: String
    var workspaceID: String
    static var current: ServiceConfiguration {
        AccountSession.Record.load()?.configuration ?? .init(baseURL: "", token: "", workspaceID: "")
    }
    var isValid: Bool {
        Self.validAddress(baseURL) && !token.isEmpty
    }
    static func validAddress(_ address: String) -> Bool {
        guard let components = URLComponents(string: address),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return false }
        let local = ["localhost", "127.0.0.1", "::1"].contains(host)
        return components.scheme == "https" || (components.scheme == "http" && local)
    }
}

enum AIError: LocalizedError {
    case message(String)
    case quotaExhausted(String)
    var errorDescription: String? {
        switch self { case .message(let value), .quotaExhausted(let value): return value }
    }
}

struct AnalysisProgress: Codable, Equatable {
    var stage: String
    var message: String
}

struct ServiceError: Codable {
    var code: String
    var message: String
    var analysisError: AIError { code == "AI_QUOTA_EXHAUSTED" ? .quotaExhausted(message) : .message(message) }
}

struct AIClient {
    let configuration: ServiceConfiguration

    func meal(image: Data, note: String, answers: [MealClarificationAnswer] = [], analysisID: UUID, requestID: UUID,
              progress: @escaping @MainActor (AnalysisProgress) -> Void) async throws -> MealAnalysis {
        struct Input: Encodable {
            let imageBase64: String
            let note: String
            let confirmationFlow = true
            let answers: [MealClarificationAnswer]
        }
        let input = Input(imageBase64: image.base64EncodedString(), note: note, answers: answers)
        return try await request(path: "v1/analyze/meal", input: input, analysisID: analysisID, requestID: requestID, progress: progress)
    }

    func metabolism(profile: Profile, progress: @escaping @MainActor (AnalysisProgress) -> Void) async throws -> MetabolismResponse {
        struct Input: Encodable { var sex: String; var age: Int; var heightCM: Double; var weightKG: Double }
        return try await request(path: "v1/analyze/metabolism",
            input: Input(sex: profile.sex.rawValue, age: profile.age, heightCM: profile.heightCM, weightKG: profile.weightKG), progress: progress)
    }

    private func request<Input: Encodable, Output: Decodable>(path: String, input: Input, analysisID: UUID = UUID(), requestID: UUID = UUID(),
        progress: @escaping @MainActor (AnalysisProgress) -> Void) async throws -> Output {
        guard configuration.isValid, let base = URL(string: configuration.baseURL) else {
            throw AIError.message("请先在“我的 → NAS 账号”登录。")
        }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 150
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(analysisID.uuidString, forHTTPHeaderField: "X-Analysis-ID")
        request.setValue(requestID.uuidString, forHTTPHeaderField: "X-Request-ID")
        request.httpBody = try JSONEncoder().encode(input)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 150
        sessionConfiguration.timeoutIntervalForResource = 160
        let session = URLSession(configuration: sessionConfiguration, delegate: DirectServiceRequest(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIError.message("服务器没有返回有效响应。") }
            guard http.statusCode == 200 else {
                var body = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    guard body.count < 8192 else { break }
                    body.append(byte)
                }
                if let error = try? JSONDecoder().decode(ServiceError.self, from: body) { throw error.analysisError }
                throw AIError.message("服务连接失败（\(http.statusCode)），请检查 NAS 地址或重新登录。")
            }
            guard http.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true else {
                throw AIError.message("服务返回格式不正确，请检查后端地址。")
            }
            var parser = AnalysisEventParser()
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard let frame = try parser.consume(line) else { continue }
                switch frame.name {
                case "progress":
                    let update = try JSONDecoder().decode(AnalysisProgress.self, from: frame.data)
                    await progress(update)
                case "result": return try JSONDecoder().decode(Output.self, from: frame.data)
                case "error":
                    let error = try JSONDecoder().decode(ServiceError.self, from: frame.data)
                    throw error.analysisError
                default: break
                }
            }
            throw AIError.message("连接中断，结果尚未保存。请重试。")
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            if error.code == .timedOut { throw AIError.message("分析超时，照片草稿仍在，可以重试或手动记录。") }
            throw AIError.message("网络连接失败，请检查网络及服务地址后重试。")
        }
    }
}
