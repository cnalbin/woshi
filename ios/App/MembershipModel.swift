import SwiftUI
import StoreKit

struct MembershipStatus: Decodable {
    let enabled: Bool
    let purchaseEnabled: Bool
    let productID: String
    let accountToken: UUID
    let active: Bool
    let expiresAt: String?
    let willRenew: Bool?
    let remaining: Int
    let limit: Int
    let model: String
    let skin: AppSkin

    var renewalDate: String? {
        guard let expiresAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: expiresAt) ?? ISO8601DateFormatter().date(from: expiresAt)
        return date?.formatted(.dateTime.month().day())
    }
}

@MainActor
final class MembershipModel: ObservableObject {
    @Published private(set) var status: MembershipStatus?
    @Published private(set) var product: Product?
    @Published private(set) var busy = false
    @Published var message: String?
    let service: ServiceConfiguration
    private var refreshTask: Task<Void, Never>?
    private var stateRevision = 0

    init(service: ServiceConfiguration) { self.service = service }

    func refresh() async {
        if let refreshTask { await refreshTask.value; return }
        let revision = stateRevision
        let task = Task {
            do {
                let data = try await CloudClient(configuration: service).request("v1/membership", method: "GET")
                let value = try JSONDecoder().decode(MembershipStatus.self, from: data)
                if revision == stateRevision { status = value }
            } catch { /* Settings can retry when connectivity returns. */ }
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    func loadProduct() async {
        if status == nil { await refresh() }
        guard let status, status.purchaseEnabled else { return }
        do {
            product = try await Product.products(for: [status.productID]).first { $0.id == status.productID }
            if product == nil { message = "当前商店暂时无法提供会员订阅。" }
        } catch { message = error.localizedDescription }
    }

    func purchase() async {
        guard !busy, let product, let token = status?.accountToken else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            switch try await product.purchase(options: [.appAccountToken(token)]) {
            case .success(let result): try await submit(result)
            case .pending: message = "购买正在等待 Apple 确认。"
            case .userCancelled: break
            @unknown default: message = "暂时无法确认购买结果。"
            }
        } catch { message = error.localizedDescription }
    }

    func restore() async {
        guard !busy, status?.purchaseEnabled == true else { return }
        busy = true; message = nil
        defer { busy = false }
        do {
            try await StoreKit.AppStore.sync()
            try await syncEntitlements()
            await refresh()
            if status?.active != true { message = "当前 Apple 账号没有可恢复的轻记会员。" }
        } catch { message = error.localizedDescription }
    }

    func observeTransactions() async {
        await refresh()
        if status?.purchaseEnabled == true { try? await syncEntitlements() }
        for await result in StoreKit.Transaction.updates {
            if status?.purchaseEnabled == true { try? await submit(result) }
        }
    }

    func update(model: String? = nil, skin: AppSkin? = nil) async throws {
        struct Preferences: Encodable { let model: String?; let skin: AppSkin? }
        let body = try JSONEncoder().encode(Preferences(model: model, skin: skin))
        let data = try await CloudClient(configuration: service).request("v1/membership/preferences", method: "PUT", data: body)
        stateRevision += 1
        status = try JSONDecoder().decode(MembershipStatus.self, from: data)
    }

    private func syncEntitlements() async throws {
        for await result in StoreKit.Transaction.currentEntitlements { try await submit(result) }
    }

    private func submit(_ result: VerificationResult<StoreKit.Transaction>) async throws {
        guard case .verified(let transaction) = result, transaction.productID == status?.productID else { return }
        struct Signed: Encodable { let signedTransaction: String }
        let body = try JSONEncoder().encode(Signed(signedTransaction: result.jwsRepresentation))
        let data = try await CloudClient(configuration: service).request("v1/membership/apple/transaction", method: "POST", data: body)
        stateRevision += 1
        status = try JSONDecoder().decode(MembershipStatus.self, from: data)
        await transaction.finish()
    }
}
