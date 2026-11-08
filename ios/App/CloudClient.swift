import Foundation
import CryptoKit

struct CloudPhoto: Codable { var filename: String; var sha256: String }
struct CloudEnvelope: Codable {
    var revision: Int
    var updatedAt: String?
    var snapshot: AppSnapshot?
    var photos: [CloudPhoto]
}
struct CloudReceipt: Codable { var revision: Int; var updatedAt: String }
struct CloudSubmission: Encodable {
    var expectedRevision: Int
    var snapshot: AppSnapshot
    var photos: [CloudPhoto]
}
struct CloudState: Codable {
    var enabled = false
    var identity = ""
    var revision: Int?
    var lastSynced: Date?
    var lastRestoreFolder: String?
    var lastSnapshotHash: String?
}

enum CloudError: LocalizedError {
    case conflict, message(String)
    var errorDescription: String? {
        switch self {
        case .conflict: return "NAS 已有更新数据，本机记录已保留，未覆盖 NAS。请先查看并恢复 NAS 备份。"
        case .message(let text): return text
        }
    }
}

struct CloudClient {
    let configuration: ServiceConfiguration
    var identity: String { configuration.workspaceID }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func read() async throws -> CloudEnvelope {
        try JSONDecoder().decode(CloudEnvelope.self, from: await request("v1/backup", method: "GET"))
    }
    func write(_ value: CloudSubmission) async throws -> CloudReceipt {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(CloudReceipt.self, from: await request("v1/backup", method: "PUT", data: data))
    }
    func upload(_ data: Data, digest: String) async throws {
        _ = try await request("v1/photos/\(digest)", method: "PUT", data: data, contentType: "application/octet-stream")
    }
    func download(digest: String) async throws -> Data {
        guard digest.count == 64, digest.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { throw CloudError.message("照片标识无效。") }
        let data = try await request("v1/photos/\(digest)", method: "GET", maximum: 4_000_000)
        guard Self.hash(data) == digest else { throw CloudError.message("下载照片的校验值不一致，本机资料尚未替换。") }
        return data
    }

    func request(_ path: String, method: String, data: Data? = nil,
                         contentType: String = "application/json", maximum: Int = 24_000_000) async throws -> Data {
        guard configuration.isValid, let base = URL(string: configuration.baseURL) else {
            throw CloudError.message("请先登录 NAS 账号。")
        }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = data
        request.timeoutInterval = 90
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        if data != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        let session = URLSession(configuration: .ephemeral, delegate: DirectServiceRequest(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw CloudError.message("NAS 响应无效。") }
        var result = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard result.count < maximum else { throw CloudError.message("NAS 响应过大，已停止下载。") }
            result.append(byte)
        }
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 409 { throw CloudError.conflict }
            let message = (try? JSONDecoder().decode(ServiceError.self, from: result))?.message
            throw CloudError.message(message ?? "NAS 连接失败（\(response.statusCode)），本机资料仍然保留。")
        }
        return result
    }
}
