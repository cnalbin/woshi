import SwiftUI

@main
struct QingJiApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var health = HealthService()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environmentObject(health).tint(Theme.green)
                .task { health.start() }
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
