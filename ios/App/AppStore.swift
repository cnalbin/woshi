import SwiftUI
import UIKit

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snapshot = AppSnapshot()
    @Published var errorMessage: String?
    @Published private(set) var storageUnavailable = false
    private let folder: URL
    private let file: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = documents.appendingPathComponent("QingJi", isDirectory: true)
        file = folder.appendingPathComponent("records.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var resourceURL = folder
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try resourceURL.setResourceValues(values)
            if FileManager.default.fileExists(atPath: file.path) {
                let data = try Data(contentsOf: file)
                let loaded = try JSONDecoder().decode(AppSnapshot.self, from: data)
                guard loaded.schemaVersion == 1, loaded.profile?.isValid != false,
                      loaded.meals.allSatisfy(\.isValid) else { throw StorageError.invalidData }
                snapshot = loaded
            }
        } catch {
            storageUnavailable = true
            errorMessage = "无法读取本地记录，原始文件已保留。请保留应用数据并联系开发者恢复，暂时不要卸载。"
        }
    }

    private func commit(_ next: AppSnapshot) throws {
        guard !storageUnavailable else { throw StorageError.unavailable }
        let data = try JSONEncoder().encode(next)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        snapshot = next
    }

    func saveProfile(_ profile: Profile) throws {
        guard profile.isValid else { throw StorageError.invalidData }
        var next = snapshot
        next.profile = profile
        // Preserve the previous assessment for transparency; stale values are never blended.
        try commit(next)
    }

    func setAIConsent(_ consent: Bool) throws {
        var next = snapshot
        next.aiConsent = consent
        try commit(next)
    }

    func saveAssessment(_ response: MetabolismResponse, for profile: Profile) throws {
        guard snapshot.profile?.fingerprint == profile.fingerprint,
              response.estimatedKcal.isFinite, (600...5000).contains(response.estimatedKcal) else {
            throw StorageError.invalidData
        }
        var next = snapshot
        next.metabolism = MetabolismAssessment(response: response, profileFingerprint: profile.fingerprint)
        try commit(next)
    }

    /// Upsert by stable UUID makes double-taps and retries idempotent.
    func saveMeal(_ meal: Meal, photo: Data?) throws {
        guard meal.isValid else { throw StorageError.invalidData }
        var saved = meal
        let newPhoto = photo != nil && saved.photoFilename == nil
        if let photo, newPhoto {
            let name = "\(meal.id.uuidString).jpg"
            try photo.write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
            saved.photoFilename = name
        }
        var next = snapshot
        if let index = next.meals.firstIndex(where: { $0.id == meal.id }) { next.meals[index] = saved }
        else { next.meals.append(saved) }
        do { try commit(next) }
        catch {
            if newPhoto, let name = saved.photoFilename { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
            throw error
        }
    }

    func deleteMeal(_ meal: Meal) throws {
        var next = snapshot
        next.meals.removeAll { $0.id == meal.id }
        try commit(next)
        if let filename = meal.photoFilename { try? FileManager.default.removeItem(at: folder.appendingPathComponent(filename)) }
    }

    func photo(for meal: Meal) -> UIImage? {
        guard let filename = meal.photoFilename, !filename.contains("/"), !filename.contains("\\") else { return nil }
        return UIImage(contentsOfFile: folder.appendingPathComponent(filename).path)
    }

    enum StorageError: LocalizedError {
        case invalidData, unavailable
        var errorDescription: String? {
            switch self {
            case .invalidData: return "资料或记录不完整，请检查后重试。"
            case .unavailable: return "本地存储暂不可用，原始数据已保留。"
            }
        }
    }
}
