import SwiftData
import SwiftUI
import TripCore

/// Bottom sheet for a tapped region: status, its trips, mark/unmark, new trip.
struct RegionSheet: View {
    let ref: RegionRef
    var onOpenPack: ((String) -> Void)?

    @Environment(MapPackStore.self) private var store
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var matches: [VisitedRegion]
    @Query private var allMarks: [VisitedRegion]
    @State private var showEditor = false
    @State private var confirmUnmark = false

    init(ref: RegionRef, onOpenPack: ((String) -> Void)? = nil) {
        self.ref = ref
        self.onOpenPack = onOpenPack
        let key = ref.key
        _matches = Query(filter: #Predicate<VisitedRegion> { $0.regionKey == key })
    }

    private var mark: VisitedRegion? { matches.first }
    private var region: MapRegion? { store.region(ref) }
    private var trips: [Trip] { mark?.tripList ?? [] }
    private var isHome: Bool { app.homeRegionKey == ref.key }

    var body: some View {
        NavigationStack {
            List {
                Section { header }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

                if let sub = store.subpack(for: ref) {
                    subpackSection(sub)
                }

                Section {
                    ForEach(trips) { trip in
                        NavigationLink(value: trip) {
                            TripRow(trip: trip, showPlace: false)
                        }
                    }
                    Button {
                        showEditor = true
                    } label: {
                        Label("Yeni gezi ekle", systemImage: "plus.circle.fill")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityIdentifier("region.newTrip")
                } header: {
                    Text(trips.isEmpty ? "Geziler" : "Geziler (\(trips.count))")
                } footer: {
                    if trips.isEmpty {
                        Text("Aynı yere farklı tarihlerde birden fazla gezi ekleyebilirsin.")
                    }
                }

                Section {
                    if mark == nil {
                        Button {
                            context.markVisited(ref)
                            try? context.save()
                            app.paint(ref)
                        } label: {
                            Label("Gittim olarak işaretle", systemImage: "checkmark.circle")
                        }
                        .accessibilityIdentifier("region.mark")
                    } else {
                        Button(role: .destructive) {
                            if trips.isEmpty { unmark() } else { confirmUnmark = true }
                        } label: {
                            Label("İşareti kaldır", systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .navigationTitle(region?.name ?? ref.regionID)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Trip.self) { TripDetailScreen(trip: $0) }
            .sheet(isPresented: $showEditor) {
                TripEditorView(mode: .create(region: ref))
            }
            .confirmationDialog("İşaret kaldırılsın mı?", isPresented: $confirmUnmark, titleVisibility: .visible) {
                Button("\(trips.count) geziyle birlikte sil", role: .destructive) { unmark() }
            } message: {
                Text("Bu yere ait geziler, notlar ve eklenen medya kayıtları silinecek. Galerindeki fotoğraflar silinmez.")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(region?.name ?? ref.regionID)
                .font(.largeTitle.weight(.bold))
            HStack(spacing: 8) {
                if let region { Chip(text: region.group, systemImage: "mappin.and.ellipse", tint: .secondary) }
                if isHome {
                    Chip(text: "Memleketin", systemImage: "house.fill", tint: Theme.home)
                } else if mark != nil {
                    Chip(text: "Gidildi", systemImage: "checkmark.seal.fill")
                } else {
                    Chip(text: "Henüz gidilmedi", systemImage: "circle.dashed", tint: .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subpackSection(_ sub: MapPack) -> some View {
        let visited = ProgressCalculator.effectiveVisited(in: sub, marks: allMarks.map(\.ref), allPacks: store.packs)
        let progress = ProgressCalculator.progress(of: sub, visited: visited)
        return Section {
            Button {
                onOpenPack?(sub.id)
            } label: {
                HStack(spacing: 12) {
                    ProgressRing(fraction: progress.fraction, lineWidth: 5)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading) {
                        Text("\(sub.name) haritasında aç")
                            .font(.body.weight(.semibold))
                        Text("\(progress.total) \(sub.unitName)den \(progress.visited) \(sub.unitName) gezildi")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .tint(.primary)
        }
    }

    private func unmark() {
        context.unmark(ref)
        try? context.save()
    }
}

/// Compact trip row with cover, title, place and dates.
struct TripRow: View {
    let trip: Trip
    var showPlace = true

    @Environment(MapPackStore.self) private var store

    var body: some View {
        let place = store.name(of: trip.regionRef)
        HStack(spacing: 12) {
            TripCoverView(trip: trip, placeName: place, size: 64)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.title.isEmpty ? Format.autoTitle(place: place, start: trip.startDate) : trip.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(showPlace ? "\(place) · \(Format.dateRange(trip.startDate, trip.endDate, short: true))"
                     : Format.dateRange(trip.startDate, trip.endDate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    let count = trip.media?.count ?? 0
                    if count > 0 {
                        Label("\(count)", systemImage: "photo.on.rectangle")
                    }
                    if !trip.notes.isEmpty {
                        Label("Not", systemImage: "note.text")
                    }
                    if trip.source == .autoImport {
                        Label("Otomatik", systemImage: "sparkles")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, 2)
    }
}
