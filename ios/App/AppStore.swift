import SwiftUI
import UIKit

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snapshot = AppSnapshot()
    @Published var errorMessage: String?
    @Published private(set) var storageUnavailable = false
    @Published private(set) var cloudEnabled = false
    @Published private(set) var cloudSyncing = false
    @Published private(set) var cloudMessage = "等待同步"
    @Published private(set) var cloudLastSynced: Date?
    @Published private(set) var canUndoRestore = false
    private var cloudState = CloudState()
    private var cloudTask: Task<Void, Never>?
    private var generation = 0
    private let folder: URL
    private let file: URL
    private let workspaceID: String
    private let legacyFolder: URL

    init(workspaceID: String) {
        self.workspaceID = workspaceID
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        legacyFolder = documents.appendingPathComponent("QingJi", isDirectory: true)
        folder = workspaceID.isEmpty ? legacyFolder : documents.appendingPathComponent("QingJiAccounts", isDirectory: true)
            .appendingPathComponent(workspaceID, isDirectory: true)
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
            if let data = try? Data(contentsOf: folder.appendingPathComponent("cloud-state.json")),
               let state = try? JSONDecoder().decode(CloudState.self, from: data) {
                cloudState = state
                cloudEnabled = !workspaceID.isEmpty && state.enabled
                cloudLastSynced = state.lastSynced
                canUndoRestore = state.lastRestoreFolder != nil
                cloudMessage = cloudEnabled ? "本机修改将在前台自动备份到 NAS" : "NAS 自动备份已关闭"
            }
        } catch {
            storageUnavailable = true
            errorMessage = "无法读取本地记录，原始文件已保留。请保留应用数据并联系开发者恢复，暂时不要卸载。"
        }
    }

    var service: ServiceConfiguration {
        let current = ServiceConfiguration.current
        return current.workspaceID == workspaceID ? current : .init(baseURL: "", token: "", workspaceID: "")
    }

    var canImportLegacy: Bool {
        guard !workspaceID.isEmpty, service.isValid,
              UserDefaults.standard.string(forKey: "legacyMigrationWorkspace") == workspaceID else { return false }
        return snapshot.profile == nil && snapshot.meals.isEmpty && snapshot.activityDays.isEmpty
            && FileManager.default.fileExists(atPath: legacyFolder.appendingPathComponent("records.json").path)
    }

    func importLegacy() throws {
        guard canImportLegacy, !storageUnavailable else { throw StorageError.unavailable }
        let data = try Data(contentsOf: legacyFolder.appendingPathComponent("records.json"))
        var copy = try JSONDecoder().decode(AppSnapshot.self, from: data)
        guard copy.schemaVersion == 1, copy.profile?.isValid != false,
              copy.meals.allSatisfy(\.isValid) else { throw StorageError.invalidData }
        for name in Set(copy.meals.compactMap(\.photoFilename)) {
            guard Self.safePhotoName(name) else { throw StorageError.invalidData }
            try Data(contentsOf: legacyFolder.appendingPathComponent(name))
                .write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        }
        copy.aiConsent = false
        try commit(copy, schedule: false)
    }

    private func commit(_ next: AppSnapshot, schedule: Bool = true) throws {
        guard !storageUnavailable else { throw StorageError.unavailable }
        let data = try JSONEncoder().encode(next)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        snapshot = next
        generation += 1
        if schedule { scheduleCloudBackup() }
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

    func saveActivity(_ value: ActivityDay) {
        guard value.activeKcal.isFinite, value.activeKcal >= 0 else { return }
        if let old = snapshot.activityDays.first(where: { $0.id == value.id }), abs(old.activeKcal - value.activeKcal) < 0.01 { return }
        var next = snapshot
        next.activityDays.removeAll { $0.id == value.id }
        next.activityDays.append(value)
        do { try commit(next) } catch { errorMessage = error.localizedDescription }
    }

    private func saveCloudState() throws {
        try JSONEncoder().encode(cloudState).write(to: folder.appendingPathComponent("cloud-state.json"), options: [.atomic, .completeFileProtection])
        cloudEnabled = cloudState.enabled
        cloudLastSynced = cloudState.lastSynced
        canUndoRestore = cloudState.lastRestoreFolder != nil
    }

    private func serviceConfigurationChanged() {
        let identity = service.workspaceID
        if cloudState.identity != identity {
            cloudTask?.cancel()
            cloudState.enabled = false
            cloudState.identity = identity
            cloudState.revision = nil
            cloudState.lastSynced = nil
            cloudState.lastSnapshotHash = nil
            try? saveCloudState()
            cloudMessage = "服务配置已变化，请重新启用备份或从 NAS 恢复"
        }
    }

    func setCloudEnabled(_ value: Bool) {
        guard !storageUnavailable, service.isValid else { return }
        serviceConfigurationChanged()
        cloudState.enabled = value
        do {
            try saveCloudState()
            cloudMessage = value ? "已启用，等待备份" : "自动备份已关闭，本机和 NAS 数据均保留"
            if value { scheduleCloudBackup() } else { cloudTask?.cancel() }
        } catch { cloudMessage = error.localizedDescription }
    }

    func scheduleCloudBackup() {
        guard service.isValid else { return }
        cloudTask?.cancel()
        cloudTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(2)); try Task.checkCancellation() }
            catch { return }
            await backupToCloud()
        }
    }

    func cancelCloudBackup() { cloudTask?.cancel() }

    private func backupSnapshot() throws -> (AppSnapshot, String) {
        var copy = snapshot
        copy.aiConsent = false
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (copy, CloudClient.hash(try encoder.encode(copy)))
    }

    func backupToCloud(onlyIfChanged: Bool = false, keepLocal: Bool = false) async {
        let configuration = service
        guard !cloudSyncing, !storageUnavailable, configuration.isValid else { return }
        cloudSyncing = true
        let savedGeneration = generation
        var settledGeneration = savedGeneration
        defer {
            cloudSyncing = false
            if generation != settledGeneration { scheduleCloudBackup() }
        }
        do {
            let client = CloudClient(configuration: configuration)
            let remote = try await client.read()
            let baselineFile = folder.appendingPathComponent("sync-baseline.json")
            let baseline = (try? JSONDecoder().decode(AppSnapshot.self, from: Data(contentsOf: baselineFile))) ?? AppSnapshot()
            var merged = snapshot
            if !keepLocal {
                merged = try SnapshotMerge.merge(base: baseline, local: snapshot, remote: remote.snapshot ?? AppSnapshot())
            }
            let names = Set(merged.meals.compactMap(\.photoFilename))
            for reference in remote.photos where names.contains(reference.filename) {
                guard Self.safePhotoName(reference.filename) else { throw StorageError.invalidData }
                let destination = folder.appendingPathComponent(reference.filename)
                if !FileManager.default.fileExists(atPath: destination.path) {
                    let data = try await client.download(digest: reference.sha256)
                    try data.write(to: destination, options: [.atomic, .completeFileProtection])
                }
            }
            var references: [CloudPhoto] = []
            let uploaded = Set(remote.photos.map(\.sha256))
            for name in names.sorted() {
                guard Self.safePhotoName(name) else { throw StorageError.invalidData }
                let data = try Data(contentsOf: folder.appendingPathComponent(name))
                let digest = CloudClient.hash(data)
                if !uploaded.contains(digest) { try await client.upload(data, digest: digest) }
                references.append(CloudPhoto(filename: name, sha256: digest))
            }
            guard savedGeneration == generation, client.identity == service.workspaceID else { return }
            // Persist downloaded records before uploading, so a process interruption preserves edits.
            merged.aiConsent = snapshot.aiConsent
            try commit(merged, schedule: false)
            settledGeneration = generation
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            var upload = merged
            upload.aiConsent = false
            let remoteData = try remote.snapshot.map { try encoder.encode($0) }
            let localData = try encoder.encode(upload)
            if remoteData != localData {
                _ = try await client.write(CloudSubmission(expectedRevision: remote.revision, snapshot: upload, photos: references))
            }
            try JSONEncoder().encode(upload).write(to: baselineFile, options: [.atomic, .completeFileProtection])
            cloudState.lastSynced = Date()
            cloudState.enabled = true
            cloudState.identity = client.identity
            try saveCloudState()
            cloudMessage = generation == settledGeneration ? "已同步" : "等待同步"
        } catch SnapshotMerge.Conflict.concurrentEdit {
            cloudMessage = "同一记录在其他设备有修改，请在数据同步页选择版本"
        } catch { cloudMessage = "等待同步 · " + error.localizedDescription }
    }

    func restoreFromCloud() async {
        let configuration = service
        guard !cloudSyncing, !storageUnavailable, configuration.isValid else { return }
        cloudTask?.cancel()
        cloudSyncing = true
        let savedGeneration = generation
        let client = CloudClient(configuration: configuration)
        let staging = folder.appendingPathComponent("restore-staging-\(UUID().uuidString)", isDirectory: true)
        defer { cloudSyncing = false; try? FileManager.default.removeItem(at: staging) }
        do {
            cloudMessage = "正在读取 NAS 记录…"
            let remote = try await client.read()
            guard var copy = remote.snapshot, copy.schemaVersion == 1, copy.profile?.isValid != false,
                  copy.meals.allSatisfy(\.isValid) else { throw CloudError.message("NAS 没有可恢复的有效备份，本机资料未改变。") }
            let names = Set(copy.meals.compactMap(\.photoFilename))
            guard names == Set(remote.photos.map(\.filename)), names.count == remote.photos.count,
                  names.allSatisfy(Self.safePhotoName) else { throw CloudError.message("NAS 照片清单不完整，已停止恢复。") }
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            for (index, reference) in remote.photos.enumerated() {
                cloudMessage = "正在恢复照片 \(index + 1)/\(remote.photos.count)…"
                let data = try await client.download(digest: reference.sha256)
                try data.write(to: staging.appendingPathComponent(reference.filename), options: [.atomic, .completeFileProtection])
            }
            guard generation == savedGeneration, client.identity == service.workspaceID else {
                throw CloudError.message("下载期间本机记录或服务配置发生变化，请重新恢复；没有覆盖本机数据。")
            }
            let recoveryName = "before-restore-\(UUID().uuidString)"
            let recovery = folder.appendingPathComponent(recoveryName, isDirectory: true)
            try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: recovery.appendingPathComponent("records.json"), options: [.atomic, .completeFileProtection])
            for name in Set(snapshot.meals.compactMap(\.photoFilename)) where Self.safePhotoName(name) {
                let source = folder.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: source.path) { try FileManager.default.copyItem(at: source, to: recovery.appendingPathComponent(name)) }
            }
            cloudState.lastRestoreFolder = recoveryName
            cloudState.enabled = false
            try saveCloudState()
            var restoredNames: [String: String] = [:]
            for reference in remote.photos {
                let data = try Data(contentsOf: staging.appendingPathComponent(reference.filename))
                let original = folder.appendingPathComponent(reference.filename)
                if FileManager.default.fileExists(atPath: original.path) {
                    if CloudClient.hash(try Data(contentsOf: original)) == reference.sha256 { continue }
                    let name = UUID().uuidString + ".jpg"
                    try data.write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
                    restoredNames[reference.filename] = name
                } else {
                    try data.write(to: original, options: [.atomic, .completeFileProtection])
                }
            }
            for index in copy.meals.indices {
                if let name = copy.meals[index].photoFilename, let replacement = restoredNames[name] {
                    copy.meals[index].photoFilename = replacement
                }
            }
            copy.aiConsent = snapshot.aiConsent
            try commit(copy, schedule: false)
            try JSONEncoder().encode(copy).write(to: folder.appendingPathComponent("sync-baseline.json"), options: [.atomic, .completeFileProtection])
            cloudState.identity = client.identity
            cloudState.revision = remote.revision
            cloudState.lastSynced = Date()
            cloudState.lastSnapshotHash = try backupSnapshot().1
            try saveCloudState()
            cloudMessage = "已从 NAS 恢复 \(copy.meals.count) 条饮食记录及照片；可重新开启自动备份"
        } catch { cloudMessage = error.localizedDescription }
    }

    func undoLastRestore() {
        guard !cloudSyncing, let name = cloudState.lastRestoreFolder, name.hasPrefix("before-restore-"), !name.contains("/") else { return }
        do {
            let recovery = folder.appendingPathComponent(name, isDirectory: true)
            let copy = try JSONDecoder().decode(AppSnapshot.self, from: Data(contentsOf: recovery.appendingPathComponent("records.json")))
            guard copy.schemaVersion == 1, copy.meals.allSatisfy(\.isValid) else { throw StorageError.invalidData }
            for name in Set(copy.meals.compactMap(\.photoFilename)) {
                guard Self.safePhotoName(name) else { throw StorageError.invalidData }
                try Data(contentsOf: recovery.appendingPathComponent(name)).write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
            }
            try commit(copy, schedule: false)
            cloudState.enabled = false
            cloudState.revision = nil
            cloudState.lastSnapshotHash = nil
            cloudState.lastRestoreFolder = nil
            try saveCloudState()
            cloudMessage = "已撤销上次恢复；自动备份关闭，NAS 数据没有改变"
        } catch { cloudMessage = error.localizedDescription }
    }

    private static func safePhotoName(_ name: String) -> Bool {
        name.hasSuffix(".jpg") && UUID(uuidString: String(name.dropLast(4))) != nil
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
