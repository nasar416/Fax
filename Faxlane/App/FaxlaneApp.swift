import SwiftUI

@main
struct FaxlaneApp: App {
    @State private var model = AppModel()
    @State private var store = StoreManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(store)
                .tint(Brand.blue)
                .task {
                    store.onPurchasesChanged = { [model] in
                        guard let api = model.api else { return }
                        if let account = try? await api.syncPurchases() { model.apply(account) }
                    }
                    // RevenueCat's App User ID is the Faxlane account ID (remembered from the last launch).
                    store.configure(appUserID: model.accountID)
                    await model.loadRemoteConfig()
                    await model.syncAccount()
                    if let id = model.accountID { await store.logIn(id) }
                    await store.loadProducts()
                    if model.api == nil, let active = store.activePlan {
                        model.plan = active.tier
                        model.period = active.period
                    }
                    await model.refreshFaxes()
                }
                .onChange(of: model.accountID) { _, id in
                    // Sign in with Apple can move this device to another account.
                    if let id { Task { await store.logIn(id) } }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.remoteConfig.requiresUpdate(current: model.appVersion) {
                ForceUpdateView()
            } else if model.remoteConfig.maintenance {
                MaintenanceView()
            } else {
                switch model.stage {
                case .language: LanguageView()
                case .onboarding: OnboardingView()
                case .restored: RestoredView()
                case .main: MainTabView()
                }
            }
        }
        .animation(.easeInOut, value: model.stage)
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = Tab.home

    enum Tab: Hashable { case home, send, faxes, settings }

    var body: some View {
        // Built with Xcode 26 this tab bar gets the Liquid Glass look automatically.
        TabView(selection: $tab) {
            NavigationStack { HomeView(selectedTab: $tab) }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Tab.home)
            NavigationStack { SendView() }
                .tabItem { Label("Send", systemImage: "paperplane") }
                .tag(Tab.send)
            NavigationStack { FaxesView() }
                .tabItem { Label("Faxes", systemImage: "tray") }
                .badge(model.unreadCount)
                .tag(Tab.faxes)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
    }
}
