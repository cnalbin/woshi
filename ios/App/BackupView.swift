import SwiftUI

struct BackupView: View {
    @EnvironmentObject private var store: AppStore
    @State private var enableConfirmation = false
    @State private var restoreConfirmation = false
    @State private var undoConfirmation = false

    var body: some View {
        Form {
            Section {
                NavigationLink { ServiceSettingsView() } label: { Label("NAS 服务地址与令牌", systemImage: "network") }
                Toggle("自动备份到 NAS", isOn: Binding(get: { store.cloudEnabled }, set: { enabled in
                    if enabled { enableConfirmation = true }
                    else { store.setCloudEnabled(false) }
                })).disabled(store.cloudSyncing || store.snapshot.profile == nil || !ServiceConfiguration.current.isValid)
                    .accessibilityIdentifier("backup.enable")
                if store.cloudSyncing { ProgressView().accessibilityLabel("正在处理 NAS 数据") }
                Text(store.cloudMessage).accessibilityIdentifier("backup.status")
                if let date = store.cloudLastSynced {
                    LabeledContent("上次备份或恢复", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                Button("立即备份") { Task { await store.backupToCloud() } }
                    .disabled(store.cloudSyncing || !store.cloudEnabled)
                    .accessibilityIdentifier("backup.upload")
            } footer: {
                Text("启用后，App 在前台把个人资料、已保存的饮食和照片、代谢结果及每日活动能量汇总备份到你的 NAS。离线时继续记餐，回到前台后重试。")
            }
            Section {
                Button("从 NAS 恢复") { restoreConfirmation = true }
                    .disabled(store.cloudSyncing || !ServiceConfiguration.current.isValid)
                    .accessibilityIdentifier("backup.restore")
                if store.canUndoRestore {
                    Button("撤销上次恢复") { undoConfirmation = true }.disabled(store.cloudSyncing)
                }
            } footer: {
                Text("换机时填写同一 NAS 服务地址和令牌即可恢复。恢复前会保存本机副本。若 NAS 版本已变化，备份会停止，以免覆盖其他设备的记录。")
            }
        }
        .navigationTitle("NAS 备份与恢复").navigationBarTitleDisplayMode(.inline)
        .alert("启用 NAS 备份？", isPresented: $enableConfirmation) {
            Button("启用备份") { store.setCloudEnabled(true) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将个人资料、饮食、照片、代谢结果和已读取的苹果健康活动汇总保存到你配置的私人 NAS。")
        }
        .alert("恢复 NAS 数据？", isPresented: $restoreConfirmation) {
            Button("恢复") { Task { await store.restoreFromCloud() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将使用 NAS 备份替换本机资料和记录。原有数据会另存一份，可撤销恢复。")
        }
        .alert("撤销上次恢复？", isPresented: $undoConfirmation) {
            Button("撤销恢复") { store.undoLastRestore() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本机将回到上次恢复前的记录，NAS 数据保持原样。请先保存恢复后新增的重要记录。")
        }
    }
}
