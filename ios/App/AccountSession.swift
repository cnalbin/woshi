import Foundation
import SwiftUI

final class DirectServiceRequest: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class AccountSession: ObservableObject {
    struct Record: Codable {
        var baseURL: String
        var accountID: String
        var username: String
        var accessToken: String
        var legacyOwner: Bool

        var configuration: ServiceConfiguration {
            let workspace = CloudClient.hash(Data("\(baseURL)|\(accountID)".utf8))
            return ServiceConfiguration(baseURL: baseURL, token: accessToken, workspaceID: workspace)
        }

        static func load() -> Record? {
            try? JSONDecoder().decode(Record.self, from: Data(KeychainToken.load().utf8))
        }
    }

    @Published private(set) var record = Record.load()
    @Published private(set) var requiresLogin = UserDefaults.standard.bool(forKey: "nasAccountUsed")
    var lastAddress: String {
        UserDefaults.standard.string(forKey: "serviceURL") ?? "https://www.u2483924.nyat.app:63314"
    }

    func signIn(address: String, username: String, password: String, registering: Bool = false) async throws {
        struct Credentials: Encodable { let username: String; let password: String }
        struct SessionResponse: Decodable {
            let accountId: String
            let username: String
            let token: String
            let legacyOwner: Bool
        }
        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ServiceConfiguration.validAddress(clean), var components = URLComponents(string: clean),
              !username.isEmpty, !password.isEmpty else {
            throw AIError.message("请输入 NAS 的 HTTPS 地址、用户名和密码。")
        }
        components.host = components.host?.lowercased()
        if components.scheme == "https", components.port == 443 { components.port = nil }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        guard let base = components.url else { throw AIError.message("NAS 地址无效。") }
        var request = URLRequest(url: base.appendingPathComponent(registering ? "v1/auth/register" : "v1/auth/login"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Credentials(username: username, password: password))
        let session = URLSession(configuration: .ephemeral, delegate: DirectServiceRequest(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else {
            if let failure = try? JSONDecoder().decode(ServiceError.self, from: data) { throw AIError.message(failure.message) }
            throw AIError.message("NAS 登录失败，请检查地址和后端版本。")
        }
        let result = try JSONDecoder().decode(SessionResponse.self, from: data)
        let saved = Record(baseURL: base.absoluteString, accountID: result.accountId, username: result.username,
                           accessToken: result.token, legacyOwner: result.legacyOwner)
        try KeychainToken.save(String(decoding: try JSONEncoder().encode(saved), as: UTF8.self))
        if !requiresLogin, result.legacyOwner {
            UserDefaults.standard.set(saved.configuration.workspaceID, forKey: "legacyMigrationWorkspace")
        }
        UserDefaults.standard.set(saved.baseURL, forKey: "serviceURL")
        UserDefaults.standard.set(true, forKey: "nasAccountUsed")
        requiresLogin = true
        record = saved
    }

    func signOut() throws {
        guard let current = record else { return }
        try KeychainToken.save("")
        record = nil
        Task {
            guard let base = URL(string: current.baseURL) else { return }
            var request = URLRequest(url: base.appendingPathComponent("v1/auth/logout"))
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")
            let session = URLSession(configuration: .ephemeral, delegate: DirectServiceRequest(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            _ = try? await session.data(for: request)
        }
    }
}
