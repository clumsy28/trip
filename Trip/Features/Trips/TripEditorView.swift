import Photos
import PhotosUI
import SwiftData
import SwiftUI
import TripCore

/// Create or edit a trip. When photos are picked first, the place and dates are inferred from them.
struct TripEditorView: View {
    enum Mode {
        case create(region: RegionRef?)
        case edit(Trip)
    }

    let mode: Mode
    var onSaved: ((Trip) -> Void)?

    @Environment(MapPackStore.self) private var store
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var region: RegionRef?
    @State private var title = ""
    @State private var start = Calendar.current.startOfDay(for: .now)
    @State private var end = Calendar.current.startOfDay(for: .now)
    @State private var notes = ""
    @State private var datesEdited = false
    @State private var pending: [ImportedMedia] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPicker = false
    @State private var showRegionPicker = false
    @State private var isImporting = false
    @State private var inferredHint: String?
    @State private var accessDenied = false

    init(mode: Mode, onSaved: ((Trip) -> Void)? = nil) {
        self.mode = mode
        self.onSaved = onSaved
        switch mode {
        case .create(let region):
            _region = State(initialValue: region)
        case .edit(let trip):
            _region = State(initialValue: trip.regionRef)
            _title = State(initialValue: trip.title)
            _start = State(initialValue: trip.startDate)
            _end = State(initialValue: trip.endDate)
            _notes = State(initialValue: trip.notes)
            _datesEdited = State(initialValue: true)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var placeName: String? { region.map { store.name(of: $0) } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nereye?") {
                    Button {
                        showRegionPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(Theme.accent)
                            Text(region.map { store.fullName(of: $0) } ?? "Yer seç")
                                .foregroundStyle(region == nil ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("editor.place")
                    if let inferredHint {
                        Label(inferredHint, systemImage: "sparkles")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Gezi") {
                    TextField("Başlık", text: $title,
                              prompt: Text(placeName.map { Format.autoTitle(place: $0, start: start) } ?? "Başlık (isteğe bağlı)"))
                    DatePicker("Başlangıç", selection: datesBinding($start), displayedComponents: .date)
                    DatePicker("Bitiş", selection: datesBinding($end), in: start..., displayedComponents: .date)
                }

                Section("Notlar") {
                    TextField("Neler yaşadın, nereleri gördün?", text: $notes, axis: .vertical)
                        .lineLimit(4...12)
                }

                Section {
                    Button {
                        Task { await openPicker() }
                    } label: {
                        Label("Galeriden fotoğraf/video ekle", systemImage: "photo.badge.plus")
                    }
                    if isImporting {
                        HStack { ProgressView(); Text("Ekleniyor…").foregroundStyle(.secondary) }
                    }
                    if !pending.isEmpty {
                        pendingGrid
                    }
                } header: {
                    Text("Fotoğraf ve videolar")
                } footer: {
                    if accessDenied {
                        Text("Galeri erişimi kapalı. Ayarlar > Trip > Fotoğraflar'dan izin verebilirsin.")
                    } else if !isEditing && region == nil {
                        Text("İpucu: Önce fotoğrafları seçersen yeri ve tarihleri fotoğraflardan otomatik doldururuz.")
                    }
                }
            }
            .navigationTitle(isEditing ? "Geziyi düzenle" : "Yeni gezi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(region == nil || isImporting)
                        .accessibilityIdentifier("editor.save")
                }
            }
            .photosPicker(isPresented: $showPicker, selection: $pickerItems,
                          matching: .any(of: [.images, .videos]), photoLibrary: .shared())
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await importPicked(items) }
            }
            .sheet(isPresented: $showRegionPicker) {
                RegionPickerView(packIDs: MapPackStore.bundledPackIDs, title: "Nereye gittin?") { ref in
                    region = ref
                    inferredHint = nil
                }
            }
        }
    }

    private var pendingGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pending) { item in
                    AssetImageView(assetID: item.assetID, fallbackData: item.imageData,
                                   targetSize: CGSize(width: 80, height: 80))
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                pending.removeAll { $0.id == item.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.5))
                            }
                            .padding(3)
                        }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func datesBinding(_ binding: Binding<Date>) -> Binding<Date> {
        Binding(get: { binding.wrappedValue }, set: { newValue in
            binding.wrappedValue = newValue
            datesEdited = true
            if end < start { end = start }
        })
    }

    private func openPicker() async {
        if PhotoLibrary.status == .notDetermined {
            _ = await PhotoLibrary.requestAccess()
        }
        accessDenied = PhotoLibrary.status == .denied || PhotoLibrary.status == .restricted
        showPicker = true // the system picker works even without library access (we then store copies)
    }

    private func importPicked(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer { isImporting = false; pickerItems = [] }
        let imported = await MediaImporter.importItems(items)
        let known = Set(pending.compactMap(\.assetID))
        pending += imported.filter { $0.assetID == nil || !known.contains($0.assetID!) }
        inferFromPhotos()
    }

    /// Fills place/dates from the picked photos' metadata, without overriding what the user chose.
    private func inferFromPhotos() {
        let samples = pending.compactMap(\.sample)
        guard !samples.isEmpty else { return }
        let resolver = store.makeResolver()
        guard let inferred = TripClusterer.infer(from: samples, resolve: resolver.resolve) else { return }
        var parts: [String] = []
        if region == nil, let found = inferred.region {
            region = found
            parts.append(store.name(of: found))
        }
        if !datesEdited && !isEditing {
            start = Calendar.current.startOfDay(for: inferred.start)
            end = Calendar.current.startOfDay(for: inferred.end)
            parts.append(Format.dateRange(start, end))
        }
        if !parts.isEmpty {
            inferredHint = "Fotoğraflardan: " + parts.joined(separator: ", ")
        }
    }

    private func save() {
        guard let region else { return }
        let wasVisited = context.visitedRegion(for: region) != nil
        let visited = context.markVisited(region)
        let trip: Trip
        switch mode {
        case .create:
            trip = Trip(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        startDate: start, endDate: end, notes: notes)
            context.insert(trip)
            trip.region = visited
        case .edit(let existing):
            trip = existing
            trip.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            trip.startDate = start
            trip.endDate = max(start, end)
            trip.notes = notes
            if trip.regionRef != region { trip.region = visited }
        }
        let added = MediaImporter.attach(pending, to: trip)
        try? context.save()
        if !wasVisited || !isEditing { app.paint(region) }
        onSaved?(trip)
        dismiss()
        Task {
            await MediaImporter.backfillThumbnails(added)
            try? context.save()
        }
    }
}
