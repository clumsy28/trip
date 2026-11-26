import Photos
import SwiftData
import SwiftUI
import TripCore

/// Scans the photo library (on device, offline) and suggests trips from photo locations and dates.
@Observable
final class AutoImportModel {
    enum Phase: Equatable {
        case intro
        case denied
        case scanning(done: Int, total: Int)
        case results
        case finished(trips: Int, photos: Int, newPlaces: Int)
    }

    var phase: Phase = .intro
    var suggestions: [TripSuggestion] = []
    var selected: Set<String> = []
    var likelyHome: [RegionRef] = []
    var scannedCount = 0
    var locatedCount = 0
    @ObservationIgnored private var samplesByID: [String: PhotoSample] = [:]

    func start(store: MapPackStore, app: AppState, context: ModelContext) async {
        var status = PhotoLibrary.status
        if status == .notDetermined { status = await PhotoLibrary.requestAccess() }
        guard status == .authorized || status == .limited else {
            phase = .denied
            return
        }
        phase = .scanning(done: 0, total: 0)

        let existing = ((try? context.fetch(FetchDescriptor<Trip>())) ?? []).compactMap { trip -> ExistingTrip? in
            guard let ref = trip.regionRef else { return nil }
            return ExistingTrip(id: trip.id, region: ref, start: trip.startDate, end: trip.endDate,
                                assetIDs: Set((trip.media ?? []).compactMap(\.assetIdentifier)))
        }
        var options = ClusterOptions()
        if let home = app.homeRegion, !app.includeHomeInAutoImport { options.excludedRegions = [home] }

        let scan = await Self.scan(packs: store.packs, existing: existing, options: options) { done, total in
            Task { @MainActor in
                if case .scanning = self.phase { self.phase = .scanning(done: done, total: total) }
            }
        }
        samplesByID = scan.samplesByID
        scannedCount = scan.scanned
        locatedCount = scan.samplesByID.count
        suggestions = scan.result.suggestions
        likelyHome = scan.result.likelyHomeRegions.filter { $0 != app.homeRegion }
        selected = Set(suggestions.map(\.id))
        phase = .results
    }

    struct ScanOutput: Sendable {
        let result: TripClusterResult
        let samplesByID: [String: PhotoSample]
        let scanned: Int
    }

    @concurrent
    nonisolated static func scan(packs: [MapPack], existing: [ExistingTrip], options: ClusterOptions,
                                 progress: @escaping @Sendable (Int, Int) -> Void) async -> ScanOutput {
        let library = await PhotoLibrary.locatedLibrarySamples(progress: progress)
        let resolver = RegionResolver(packs: packs)
        let result = TripClusterer.suggest(samples: library.samples, existing: existing, options: options,
                                           resolve: resolver.resolve)
        var byID: [String: PhotoSample] = [:]
        for s in library.samples { byID[s.id] = s }
        return ScanOutput(result: result, samplesByID: byID, scanned: library.scanned)
    }

    func setHome(_ ref: RegionRef, app: AppState, context: ModelContext) {
        app.homeRegionKey = ref.key
        context.markVisited(ref)
        try? context.save()
        likelyHome.removeAll { $0 == ref }
        if !app.includeHomeInAutoImport {
            suggestions.removeAll { $0.region == ref }
            selected = selected.intersection(suggestions.map(\.id))
        }
    }

    func apply(store: MapPackStore, app: AppState, context: ModelContext) {
        var tripCount = 0, photoCount = 0
        var newPlaces: [RegionRef] = []
        var added: [TripMedia] = []
        for suggestion in suggestions where selected.contains(suggestion.id) {
            let media = MediaImporter.media(from: suggestion.sampleIDs.compactMap { samplesByID[$0] })
            switch suggestion.kind {
            case .newTrip:
                if context.visitedRegion(for: suggestion.region) == nil { newPlaces.append(suggestion.region) }
                let region = context.markVisited(suggestion.region, at: suggestion.start)
                let trip = Trip(title: "", startDate: suggestion.start, endDate: suggestion.end, source: .autoImport)
                context.insert(trip)
                trip.region = region
                added += MediaImporter.attach(media, to: trip)
                tripCount += 1
            case .addToExisting(let tripID):
                guard let trip = context.trip(id: tripID) else { continue }
                trip.startDate = min(trip.startDate, suggestion.start)
                trip.endDate = max(trip.endDate, suggestion.end)
                added += MediaImporter.attach(media, to: trip)
            }
            photoCount += media.count
        }
        try? context.save()
        if let first = newPlaces.first { app.paint(first) }
        phase = .finished(trips: tripCount, photos: photoCount, newPlaces: newPlaces.count)
        Task {
            await MediaImporter.backfillThumbnails(added)
            try? context.save()
        }
    }
}

struct AutoImportScreen: View {
    @Environment(MapPackStore.self) private var store
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model = AutoImportModel()

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .intro: intro
                case .denied: denied
                case .scanning(let done, let total): scanning(done: done, total: total)
                case .results: results
                case .finished(let trips, let photos, let places): finished(trips: trips, photos: photos, places: places)
                }
            }
            .navigationTitle("Gezilerini bul")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }

    // MARK: Phases

    private var intro: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.pulse)
            VStack(spacing: 10) {
                Text("Fotoğraflarından gezilerini bulalım")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Fotoğraf ve videolarının konum ve tarih bilgisine bakıp hangi şehirde ne zaman bulunduğunu çıkarıyoruz. Tarama tamamen telefonunda yapılır, hiçbir şey internete gönderilmez.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 12) {
                bullet("calendar", "Aynı şehirde 48 saatten kısa aralıklarla çekilen fotoğraflar tek gezi sayılır.")
                bullet("car.fill", "Yoldan geçerken çekilen 1–2 fotoğraf gezi sayılmaz.")
                bullet("house.fill", app.homeRegion == nil
                       ? "Haftalarca aynı yerde çekilen fotoğraflardan memleketini tahmin ederiz."
                       : "Memleketin (\(store.name(of: app.homeRegion))) gezi olarak önerilmez.")
            }
            .padding()
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer()
            Button {
                Task { await model.start(store: store, app: app, context: context) }
            } label: {
                Text("Galerimi tara")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("autoImport.start")
        }
        .padding(24)
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 22)
            Text(text).font(.subheadline)
        }
    }

    private var denied: some View {
        ContentUnavailableView {
            Label("Galeri erişimi gerekiyor", systemImage: "lock.fill")
        } description: {
            Text("Gezilerini bulabilmemiz için Ayarlar > Trip > Fotoğraflar bölümünden erişim izni vermelisin.")
        } actions: {
            Button("Ayarları aç") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func scanning(done: Int, total: Int) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: total > 0 ? Double(done) / Double(total) : nil)
                .frame(maxWidth: 240)
            Text(total > 0 ? "\(Format.number(done)) / \(Format.number(total)) fotoğraf inceleniyor…" : "Galeri hazırlanıyor…")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var results: some View {
        List {
            Section {
                Text("\(Format.number(model.scannedCount)) medyanın \(Format.number(model.locatedCount)) tanesinde konum bulundu.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.likelyHome) { ref in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("\(store.name(of: ref)) senin memleketin mi?", systemImage: "house.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.home)
                        Text("Burada haftalarca kesintisiz fotoğraf çekmişsin. Memleketin olarak ayarlarsan buradaki fotoğraflar gezi olarak önerilmez.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Memleketim olarak ayarla") { model.setHome(ref, app: app, context: context) }
                            .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
            }
            if model.suggestions.isEmpty {
                ContentUnavailableView("Yeni gezi bulunamadı", systemImage: "binoculars",
                                       description: Text("Konum bilgisi olan yeni fotoğraf bulunamadı ya da hepsi zaten gezilerinde."))
            } else {
                Section("\(model.suggestions.count) öneri") {
                    ForEach(model.suggestions) { suggestion in
                        SuggestionRow(suggestion: suggestion, isSelected: model.selected.contains(suggestion.id)) {
                            if model.selected.contains(suggestion.id) {
                                model.selected.remove(suggestion.id)
                            } else {
                                model.selected.insert(suggestion.id)
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !model.suggestions.isEmpty {
                Button {
                    model.apply(store: store, app: app, context: context)
                } label: {
                    Text("Seçilenleri ekle (\(model.selected.count))")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selected.isEmpty)
                .padding()
                .background(.bar)
                .accessibilityIdentifier("autoImport.apply")
            }
        }
    }

    private func finished(trips: Int, photos: Int, places: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "party.popper.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.bounce, value: trips)
            Text("Harika!")
                .font(.largeTitle.weight(.bold))
            Text("\(trips) gezi oluşturuldu, \(photos) fotoğraf/video eklendi" + (places > 0 ? ", \(places) yeni yer boyandı." : "."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                app.selectedTab = .map
                dismiss()
            } label: {
                Text("Haritada gör")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}

private struct SuggestionRow: View {
    let suggestion: TripSuggestion
    let isSelected: Bool
    let toggle: () -> Void

    @Environment(MapPackStore.self) private var store

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.fullName(of: suggestion.region))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(Format.dateRange(suggestion.start, suggestion.end))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                }
                HStack(spacing: 4) {
                    ForEach(suggestion.sampleIDs.prefix(5), id: \.self) { id in
                        AssetImageView(assetID: id, targetSize: CGSize(width: 64, height: 64))
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    if suggestion.sampleIDs.count > 5 {
                        Text("+\(suggestion.sampleIDs.count - 5)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44)
                    }
                }
                switch suggestion.kind {
                case .newTrip:
                    Chip(text: "Yeni gezi · \(suggestion.sampleIDs.count) medya", systemImage: "plus")
                case .addToExisting:
                    Chip(text: "Mevcut geziye \(suggestion.sampleIDs.count) medya ekle", systemImage: "arrow.down.circle",
                         tint: Theme.home)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
