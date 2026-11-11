import SwiftUI

@main
struct QingJiApp: App {
    @StateObject private var session = AccountSession()
    var body: some Scene {
        WindowGroup {
            Group {
                if session.record == nil {
                    NavigationStack { ServiceSettingsView() }
                } else if let configuration = session.record?.configuration {
                    AccountWorkspace(configuration: configuration).id(configuration.workspaceID)
                }
            }.environmentObject(session).tint(Theme.green)
        }
    }
}

struct AccountWorkspace: View {
    @StateObject private var store: AppStore
    @StateObject private var health: HealthService
    @StateObject private var membership: MembershipModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("qingji.appearanceMode") private var appearanceMode: AppearanceMode = .system

    init(configuration: ServiceConfiguration) {
        let workspace = configuration.workspaceID
        _store = StateObject(wrappedValue: AppStore(workspaceID: workspace))
        _health = StateObject(wrappedValue: HealthService(workspaceID: workspace))
        _membership = StateObject(wrappedValue: MembershipModel(service: configuration))
    }

    var body: some View {
        let skin = membership.status?.skin ?? .classic
        RootView().environmentObject(store).environmentObject(health).environmentObject(membership)
            .environment(\.appSkin, skin).tint(skin.accent).preferredColorScheme(appearanceMode.scheme)
            .task { await membership.observeTransactions() }
            .task {
                health.start()
                while !Task.isCancelled {
                    if scenePhase == .active {
                        await store.backupToCloud()
                        await membership.refresh()
                    }
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                }
            }
            .task(id: health.hasRequested) {
                if health.hasRequested {
                    let values = await health.history()
                    if !Task.isCancelled { store.saveActivities(values) }
                }
            }
            .onDisappear { health.stop(); store.cancelCloudBackup() }
            .onChange(of: health.observation) { _, observation in
                if let observation { store.saveActivity(observation) }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    store.scheduleCloudBackup()
                    Task { await membership.refresh() }
                }
            }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        TabView {
            TodayView().tabItem { Label("今日", systemImage: "house") }
            TrendsView().tabItem { Label("趋势", systemImage: "chart.bar") }
            SettingsView().tabItem { Label("我的", systemImage: "person") }
        }
        .alert("本地数据提示", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(store.errorMessage ?? "") }
    }
}
