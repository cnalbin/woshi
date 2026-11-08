import Foundation

enum SnapshotMerge {
    enum Conflict: Error { case concurrentEdit }

    static func value<T: Equatable>(_ base: T, _ local: T, _ remote: T) throws -> T {
        if local == base { return remote }
        if remote == base || local == remote { return local }
        throw Conflict.concurrentEdit
    }

    static func records<T: Identifiable & Equatable>(_ base: [T], _ local: [T], _ remote: [T]) throws -> [T] {
        let old = Dictionary(uniqueKeysWithValues: base.map { ($0.id, $0) })
        let ours = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let theirs = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        return try Set(old.keys).union(ours.keys).union(theirs.keys).compactMap {
            try value(old[$0], ours[$0], theirs[$0])
        }
    }

    static func merge(base: AppSnapshot, local: AppSnapshot, remote: AppSnapshot) throws -> AppSnapshot {
        var result = local
        result.profile = try value(base.profile, local.profile, remote.profile)
        result.metabolism = try value(base.metabolism, local.metabolism, remote.metabolism)
        result.meals = try records(base.meals, local.meals, remote.meals).sorted { $0.id.uuidString < $1.id.uuidString }
        result.activityDays = try records(base.activityDays, local.activityDays, remote.activityDays).sorted { $0.id < $1.id }
        return result
    }
}
