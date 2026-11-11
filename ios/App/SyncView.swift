import SwiftUI

struct SyncView: View {
    @Environment(\.appSkin) private var skin
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var session: AccountSession
    @State private var choice: Choice?
    @State private var serverImage: UIImage?

    private struct Choice {
        let keepLocal: Bool
        let comparison: SyncComparison
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let comparison = store.syncComparison {
                    Card(surface: Theme.orange.opacity(0.14)) {
                        Label("有记录同时被修改", systemImage: "exclamationmark.triangle.fill").font(.headline)
                    }
                    if comparison.hasMealConflict {
                        comparisonCard("服务器版本", symbol: "externaldrive", meal: comparison.serverMeal, image: serverImage)
                        comparisonCard("本机版本", symbol: "iphone", meal: comparison.localMeal, image: nil, useLocalPhoto: true)
                    } else {
                        Card {
                            Text("个人资料、代谢或活动数据在两个设备上发生变更。")
                                .font(.subheadline)
                        }
                    }
                    Text("选择将应用于整份资料。本机副本会保留。").font(.footnote).foregroundStyle(.secondary)
                } else {
                    BrandWordmark(compact: false).padding(.vertical, 10)
                    Card(surface: skin.membershipBackground) {
                        HStack(spacing: 14) {
                            Image(systemName: store.cloudMessage == "已同步" ? "checkmark.icloud" : "icloud")
                                .font(.largeTitle).foregroundStyle(skin.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(store.cloudMessage).font(.headline).accessibilityIdentifier("sync.status")
                                if let date = store.cloudLastSynced {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Card {
                        LabeledContent("当前账号", value: session.record?.username ?? "—")
                        Divider()
                        Label("资料、饮食与活动记录", systemImage: "list.bullet.rectangle")
                        Divider()
                        Label("饮食照片", systemImage: "photo")
                    }
                    Text("联网后自动同步，离线记录保存在本机。").font(.footnote).foregroundStyle(.secondary)
                }
                if store.cloudSyncing { ProgressView("正在同步…") }
            }.padding(Theme.gutter)
        }.background(skin.background)
            .navigationTitle("数据同步").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .pageActions {
                if let comparison = store.syncComparison {
                    EqualActions {
                        Button("使用服务器") { choice = Choice(keepLocal: false, comparison: comparison) }.buttonStyle(OutlineButtonStyle())
                        Button("保留本机") { choice = Choice(keepLocal: true, comparison: comparison) }.buttonStyle(PrimaryButtonStyle())
                    }.disabled(store.cloudSyncing)
                } else {
                    Button("立即同步") { Task { await store.backupToCloud() } }.buttonStyle(OutlineButtonStyle()).disabled(store.cloudSyncing)
                }
            }
            .task(id: store.syncComparison?.serverPhoto) {
                serverImage = nil
                if let photo = store.syncComparison?.serverPhoto,
                   let data = try? await CloudClient(configuration: store.service).download(digest: photo.sha256),
                   !Task.isCancelled {
                    serverImage = UIImage(data: data)
                }
            }
            .alert("确认使用所选版本？", isPresented: Binding(get: { choice != nil }, set: { if !$0 { choice = nil } })) {
                Button("确认") {
                    guard let selected = choice else { return }
                    choice = nil
                    Task {
                        if selected.keepLocal {
                            await store.backupToCloud(keepLocal: true, reviewed: selected.comparison)
                        } else {
                            await store.restoreFromCloud(reviewed: selected.comparison)
                        }
                    }
                }
                Button("取消", role: .cancel) { choice = nil }
            } message: { Text("此次同步将以所选版本的整份资料为准。") }
    }

    private func comparisonCard(_ title: String, symbol: String, meal: Meal?, image: UIImage?, useLocalPhoto: Bool = false) -> some View {
        Card {
            Label(title, systemImage: symbol).font(.headline)
            Divider()
            if let meal {
                HStack(spacing: 12) {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 55, height: 55)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    } else {
                        MealThumbnail(url: useLocalPhoto ? store.photoURL(for: meal) : nil, symbol: meal.kind.symbol)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meal.kind.label + " · " + meal.items.map(\.name).joined(separator: "、")).font(.subheadline.weight(.semibold))
                        Text(meal.consumedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        Text("\(Int(meal.totalKcal.rounded())) kcal").font(.title3.bold()).foregroundStyle(skin.accent)
                    }
                }
            } else {
                Text("此版本已删除这条饮食记录").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
