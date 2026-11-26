import SwiftData
import SwiftUI
import TripCore

struct MapScreen: View {
    @Environment(AppState.self) private var app
    @Environment(MapPackStore.self) private var store
    @Query private var marks: [VisitedRegion]
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]

    @State private var selection: RegionRef?
    @State private var pendingSelection: RegionRef?
    @State private var showSearch = false

    var body: some View {
        let renderable = store.renderable(app.selectedPackID)
        let pack = renderable.pack
        let visual = MapVisualState(pack: pack, marks: marks, store: store, home: app.homeRegion)

        NavigationStack {
            VStack(spacing: 0) {
                header(pack: pack, progress: visual.progress)
                MapCanvasView(
                    map: renderable,
                    fills: visual.fills,
                    selectedID: selection?.packID == pack.id ? selection?.regionID : nil,
                    paintEvent: selection == nil && !showSearch ? app.paintEvent : nil,
                    onPaintConsumed: { app.paintEvent = nil },
                    onTap: { id in selection = RegionRef(packID: pack.id, regionID: id) })
                    .id(pack.id)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                GroupStrip(groups: visual.progress.groups)
                RecentTripsStrip(trips: recentTrips(in: pack))
                MapLegend(showHome: visual.hasHome)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
            }
            .background(Theme.ocean.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Trip.self) { TripDetailScreen(trip: $0) }
            .task {
                #if DEBUG
                if let ref = LaunchOptions.takeOpenRegion() { selection = ref }
                #endif
            }
            .sheet(item: $selection) { ref in
                RegionSheet(ref: ref, onOpenPack: { packID in
                    selection = nil
                    withAnimation { app.selectedPackID = packID }
                })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSearch, onDismiss: {
                selection = pendingSelection
                pendingSelection = nil
            }) {
                RegionPickerView(packIDs: [pack.id], title: "\(pack.name) içinde ara") { ref in
                    pendingSelection = ref
                }
            }
        }
    }

    /// Latest trips shown under the map: this pack's places (and, on the world map, everything).
    private func recentTrips(in pack: MapPack) -> [Trip] {
        let isWorld = pack.parentRegionID == nil
        return Array(trips.lazy.filter { isWorld || $0.regionRef?.packID == pack.id }.prefix(8))
    }

    private func header(pack: MapPack, progress: PackProgress) -> some View {
        @Bindable var app = app
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                FloatingButton(systemImage: "magnifyingglass", label: "Ara", identifier: "map.search") {
                    showSearch = true
                }
                Picker("Harita", selection: $app.selectedPackID.animation()) {
                    ForEach(store.packs) { pack in
                        Text(pack.name).tag(pack.id)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("map.packPicker")
                FloatingButton(systemImage: "sparkles", label: "Fotoğraflarımdan bul", identifier: "map.autoImport") {
                    app.isAutoImportPresented = true
                }
            }
            ProgressPill(progress: progress, unitName: pack.unitName)
        }
        .padding(.top, 8)
        .padding(.horizontal)
    }
}

/// Horizontal strip of the latest trips with their covers.
struct RecentTripsStrip: View {
    let trips: [Trip]
    @Environment(MapPackStore.self) private var store

    var body: some View {
        if !trips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(trips) { trip in
                        let place = store.name(of: trip.regionRef)
                        NavigationLink(value: trip) {
                            TripCoverView(trip: trip, placeName: place, size: 160)
                                .frame(width: 128, height: 86)
                                .overlay(alignment: .bottomLeading) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(place)
                                            .font(.caption.weight(.bold))
                                        Text(Format.monthYear(trip.startDate))
                                            .font(.caption2)
                                            .opacity(0.9)
                                    }
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.4), radius: 3)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(LinearGradient(colors: [.clear, .black.opacity(0.45)],
                                                               startPoint: .top, endPoint: .bottom))
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
    }
}

/// Horizontal strip of per-region/continent mini progress rings.
struct GroupStrip: View {
    let groups: [GroupProgress]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(groups) { group in
                    HStack(spacing: 10) {
                        ProgressRing(fraction: group.fraction, lineWidth: 4)
                            .frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(group.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text("\(group.visited)/\(group.total) · \(Format.percent(group.fraction))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }
}

/// Everything the map needs to draw one pack, derived from the user's marks.
struct MapVisualState {
    let fills: [String: Color]
    let progress: PackProgress
    let hasHome: Bool

    init(pack: MapPack, marks: [VisitedRegion], store: MapPackStore, home: RegionRef?) {
        var tripCounts: [String: Int] = [:]
        for mark in marks where mark.packID == pack.id {
            tripCounts[mark.regionID, default: 0] += mark.trips?.count ?? 0
        }
        // Marks in a more detailed pack paint their parent here (İstanbul ⇒ Türkiye on the world map).
        for sub in store.packs where sub.id != pack.id {
            guard let parent = sub.parentRegionID, pack.region(parent) != nil else { continue }
            let subMarks = marks.filter { $0.packID == sub.id }
            if !subMarks.isEmpty {
                tripCounts[parent, default: 0] += subMarks.reduce(0) { $0 + ($1.trips?.count ?? 0) }
            }
        }
        var fills: [String: Color] = [:]
        for (id, count) in tripCounts { fills[id] = Theme.fill(tripCount: count) }
        var hasHome = false
        if let home, home.packID == pack.id {
            fills[home.regionID] = Theme.home
            hasHome = true
        }
        self.fills = fills
        self.hasHome = hasHome
        let visited = ProgressCalculator.effectiveVisited(in: pack, marks: marks.map(\.ref), allPacks: store.packs)
        progress = ProgressCalculator.progress(of: pack, visited: visited)
    }
}

struct ProgressPill: View {
    let progress: PackProgress
    let unitName: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressRing(fraction: progress.fraction, lineWidth: 5)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(Format.percent(progress.fraction))
                    .font(.headline.weight(.bold))
                    .contentTransition(.numericText())
                Text("\(progress.visited)/\(progress.total) \(unitName) gezildi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.vertical, 8)
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .animation(.snappy, value: progress.visited)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(progress.visited)/\(progress.total) \(unitName) gezildi")
        .accessibilityIdentifier("map.progress")
    }
}

struct MapLegend: View {
    var showHome: Bool

    var body: some View {
        HStack(spacing: 10) {
            item(Theme.visitRamp[0], "1")
            item(Theme.visitRamp[1], "2")
            item(Theme.visitRamp[2], "3+")
            if showHome { item(Theme.home, "Memleket") }
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Renkler gezi sayısını gösterir")
    }

    private func item(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text)
        }
    }
}

struct FloatingButton: View {
    let systemImage: String
    let label: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
