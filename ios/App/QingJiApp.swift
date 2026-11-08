import SwiftUI

@main
struct QingJiApp: App {
    @StateObject private var session = AccountSession()
    var body: some Scene {
        WindowGroup {
            Group {
                if session.requiresLogin && session.record == nil {
                    NavigationStack { ServiceSettingsView() }
                } else {
                    let workspace = session.record?.configuration.workspaceID ?? ""
                    AccountWorkspace(workspace: workspace).id(workspace)
                }
            }.environmentObject(session).tint(Theme.green)
        }
    }
}

struct AccountWorkspace: View {
    @StateObject private var store: AppStore
    @StateObject private var health: HealthService
    @Environment(\.scenePhase) private var scenePhase

    init(workspace: String) {
        _store = StateObject(wrappedValue: AppStore(workspaceID: workspace))
        _health = StateObject(wrappedValue: HealthService(workspaceID: workspace))
    }

    var body: some View {
        RootView().environmentObject(store).environmentObject(health)
            .task { health.start() }
            .onDisappear { health.stop(); store.cancelCloudBackup() }
            .onChange(of: health.observation) { _, observation in
                if let observation { store.saveActivity(observation) }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active { store.scheduleCloudBackup() }
            }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Group {
            if store.snapshot.profile == nil {
                ProfileEditor(onboarding: true)
            } else {
                TabView {
                    TodayView().tabItem { Label("今日", systemImage: "calendar") }
                    SettingsView().tabItem { Label("我的", systemImage: "person") }
                }
            }
        }
        .alert("本地数据提示", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(store.errorMessage ?? "") }
    }
}
