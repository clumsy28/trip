import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            Tab("Harita", systemImage: "map.fill", value: AppTab.map) {
                MapScreen()
            }
            Tab("Geziler", systemImage: "suitcase.fill", value: AppTab.trips) {
                TripListScreen()
            }
            Tab("İstatistik", systemImage: "chart.pie.fill", value: AppTab.stats) {
                StatsScreen()
            }
            Tab("Ayarlar", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsScreen()
            }
        }
        .sheet(isPresented: $app.isAutoImportPresented) {
            AutoImportScreen()
        }
        .sheet(isPresented: Binding(get: { !app.hasCompletedOnboarding },
                                    set: { if !$0 { app.hasCompletedOnboarding = true } })) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
    }
}
