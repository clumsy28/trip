import SwiftData
import SwiftUI

@main
struct TripMain: App {
    @State private var appState: AppState
    @State private var mapStore = MapPackStore()
    private let container: ModelContainer

    init() {
        let testing = LaunchOptions.isUITesting || LaunchOptions.seedDemoData
        let defaults: UserDefaults
        if testing, let volatile = UserDefaults(suiteName: "trip.volatile") {
            volatile.removePersistentDomain(forName: "trip.volatile")
            defaults = volatile
        } else {
            defaults = .standard
        }
        let state = AppState(defaults: defaults)
        if testing { state.hasCompletedOnboarding = true }
        if let tab = LaunchOptions.initialTab { state.selectedTab = tab }
        if let pack = LaunchOptions.initialPack { state.selectedPackID = pack }

        container = AppModelContainer.make(inMemory: testing)
        #if DEBUG
        if LaunchOptions.seedDemoData {
            DemoData.seed(into: container.mainContext, appState: state)
        }
        #endif
        _appState = State(initialValue: state)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(mapStore)
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}
