import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Harita", systemImage: "map") { Text("Harita") }
            Tab("Geziler", systemImage: "suitcase") { Text("Geziler") }
            Tab("İstatistik", systemImage: "chart.pie") { Text("İstatistik") }
        }
    }
}
