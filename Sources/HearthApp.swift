import SwiftUI

@main struct HearthApp: App {
    @StateObject private var store = VaultStore()
    @Environment(\.scenePhase) private var scene
    var body: some Scene {
        WindowGroup {
            Group { if store.isUnlocked { LedgerShell() } else { LoginView() } }
                .environmentObject(store)
                .tint(HearthTheme.green)
                .preferredColorScheme(.light)
                .overlay { if scene != .active { HearthPrivacyScreen() } }
                .alert("小家", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("知道了") { store.message = nil } } message: { Text(store.message ?? "") }
                .onChange(of: store.isUnlocked) { _, unlocked in if unlocked { store.refreshFeed() } }
                .onChange(of: scene) { _, phase in
                    if phase == .background { store.lock() }
                    if phase == .active, store.isUnlocked { store.refreshFeed() }
                }
        }
    }
}
