import SwiftUI

@main
struct BetweenUsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var localization = LocalizationManager.shared

    private let store = BetweenUsStore()
    @StateObject private var room = RoomWorld()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(room)
                .environment(\.locale, localization.currentLocale)
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task { await store.sceneBecameActive() }
                }
        }
    }
}
