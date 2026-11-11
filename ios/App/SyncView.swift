import SwiftUI

struct SyncView: View {
    @Environment(\.appSkin) private var skin
    @EnvironmentObject private var store: AppStore
    @State private var choice: Bool?
    var body: some View {
        Form {
            Section {
                Label(store.cloudMessage, systemImage: "icloud").accessibilityIdentifier("sync.status")
                if let date = store.cloudLastSynced {
                    LabeledContent("上次同步", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                Button("立即重试") { Task { await store.backupToCloud() } }
                if store.cloudSyncing { ProgressView("正在同步…") }
            }
            if store.cloudMessage.contains("选择版本") {
                Section("处理同时修改的记录") {
                    Button("使用服务器版本") { choice = false }
                    Button("保留本机版本") { choice = true }
                    Text("本机副本会保留。选择版本将决定此次同步以哪一份完整资料为准。")
                }
            }
        }.scrollContentBackground(.hidden).background(skin.background)
            .disabled(store.cloudSyncing).navigationTitle("数据同步").navigationBarTitleDisplayMode(.inline)
            .alert("确认使用所选版本？", isPresented: Binding(get: { choice != nil }, set: { if !$0 { choice = nil } })) {
                Button("确认") {
                    let local = choice == true
                    choice = nil
                    Task {
                        if local { await store.backupToCloud(keepLocal: true) }
                        else { await store.restoreFromCloud(); await store.backupToCloud() }
                    }
                }
                Button("取消", role: .cancel) { choice = nil }
            }
    }
}
