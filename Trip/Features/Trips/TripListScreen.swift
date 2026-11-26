import SwiftData
import SwiftUI

struct TripListScreen: View {
    @Environment(AppState.self) private var app
    @Environment(MapPackStore.self) private var store
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @State private var query = ""
    @State private var showEditor = false
    @State private var path: [Trip] = []

    private var filtered: [Trip] {
        let key = query.trimmingCharacters(in: .whitespaces).searchKey
        guard !key.isEmpty else { return trips }
        return trips.filter {
            $0.title.searchKey.contains(key) || store.name(of: $0.regionRef).searchKey.contains(key)
                || $0.notes.searchKey.contains(key)
        }
    }

    private var years: [(year: Int, trips: [Trip])] {
        let grouped = Dictionary(grouping: filtered) { Calendar.current.component(.year, from: $0.startDate) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if trips.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(years, id: \.year) { group in
                            Section {
                                ForEach(group.trips) { trip in
                                    NavigationLink(value: trip) {
                                        TripRow(trip: trip)
                                    }
                                }
                            } header: {
                                Text(String(group.year))
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .textCase(nil)
                            }
                        }
                    }
                    .searchable(text: $query, prompt: "Gezi, şehir veya not ara")
                    .overlay {
                        if filtered.isEmpty { ContentUnavailableView.search(text: query) }
                    }
                }
            }
            .navigationTitle("Geziler")
            .navigationDestination(for: Trip.self) { TripDetailScreen(trip: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        app.isAutoImportPresented = true
                    } label: {
                        Label("Fotoğraflarımdan bul", systemImage: "sparkles")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showEditor = true
                    } label: {
                        Label("Yeni gezi", systemImage: "plus")
                    }
                    .accessibilityIdentifier("trips.add")
                }
            }
            .sheet(isPresented: $showEditor) {
                TripEditorView(mode: .create(region: nil))
            }
            .task {
                #if DEBUG
                if LaunchOptions.takeOpenTrip(), let trip = trips.first(where: { !$0.notes.isEmpty }) ?? trips.first {
                    path = [trip]
                }
                #endif
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Henüz gezi yok", systemImage: "suitcase.rolling")
        } description: {
            Text("Haritada bir yere dokunup gezi ekleyebilir ya da fotoğraflarından gezilerini otomatik bulabilirsin.")
        } actions: {
            Button {
                app.isAutoImportPresented = true
            } label: {
                Label("Fotoğraflarımdan bul", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            Button("Elle gezi ekle") { showEditor = true }
        }
    }
}
