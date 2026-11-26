import PhotosUI
import SwiftData
import SwiftUI

struct TripDetailScreen: View {
    @Bindable var trip: Trip

    @Environment(MapPackStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showEditor = false
    @State private var confirmDelete = false
    @State private var viewerStart: TripMedia?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPicker = false
    @State private var isImporting = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        let place = store.name(of: trip.regionRef)
        let media = trip.mediaList
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero(place: place)

                HStack(spacing: 8) {
                    Chip(text: "\(trip.dayCount) gün", systemImage: "calendar")
                    Chip(text: "\(media.count) medya", systemImage: "photo.on.rectangle", tint: .secondary)
                    if trip.source == .autoImport {
                        Chip(text: "Otomatik bulundu", systemImage: "sparkles", tint: Theme.home)
                    }
                }
                .padding(.horizontal)

                notesCard
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Fotoğraflar ve videolar").font(.title3.weight(.bold))
                        Spacer()
                        Button {
                            Task { await openPicker() }
                        } label: {
                            Label("Ekle", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal)

                    if isImporting { ProgressView().frame(maxWidth: .infinity) }

                    if media.isEmpty {
                        Text("Bu geziye henüz fotoğraf eklenmedi.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    } else {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(media) { item in
                                MediaThumbnail(media: item, size: 140)
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay(alignment: .topTrailing) {
                                        if item.id == trip.cover?.id && media.count > 1 {
                                            Image(systemName: "star.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.white)
                                                .padding(5)
                                                .shadow(radius: 2)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { viewerStart = item }
                                    .contextMenu {
                                        Button {
                                            trip.coverMediaID = item.id
                                        } label: {
                                            Label("Kapak fotoğrafı yap", systemImage: "star")
                                        }
                                        Button(role: .destructive) {
                                            remove(item)
                                        } label: {
                                            Label("Geziden kaldır", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .background(Theme.background)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showEditor = true } label: { Label("Düzenle", systemImage: "pencil") }
                    Button { Task { await openPicker() } } label: { Label("Fotoğraf ekle", systemImage: "photo.badge.plus") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Geziyi sil", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditor) { TripEditorView(mode: .edit(trip)) }
        .fullScreenCover(item: $viewerStart) { start in
            MediaViewer(items: media, startID: start.id)
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItems,
                      matching: .any(of: [.images, .videos]), photoLibrary: .shared())
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await addPicked(items) }
        }
        .confirmationDialog("Gezi silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Geziyi sil", role: .destructive) {
                context.delete(trip)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("Notların ve medya bağlantıları silinir. Galerindeki fotoğraflar silinmez. Yer haritada işaretli kalır.")
        }
    }

    private func hero(place: String) -> some View {
        TripCoverView(trip: trip, placeName: place, size: 800)
            .frame(height: 320)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.fullName(of: trip.regionRef).uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .opacity(0.9)
                    Text(trip.title.isEmpty ? Format.autoTitle(place: place, start: trip.startDate) : trip.title)
                        .font(.largeTitle.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(Format.dateRange(trip.startDate, trip.endDate))
                        .font(.subheadline.weight(.medium))
                        .opacity(0.9)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 6)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
            }
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notlar", systemImage: "note.text")
                .font(.headline)
            if trip.notes.isEmpty {
                Button("Bu gezi hakkında bir şeyler yaz…") { showEditor = true }
                    .foregroundStyle(.secondary)
            } else {
                Text(trip.notes)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
        .card()
    }

    private func openPicker() async {
        if PhotoLibrary.status == .notDetermined { _ = await PhotoLibrary.requestAccess() }
        showPicker = true
    }

    private func addPicked(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer { isImporting = false; pickerItems = [] }
        let imported = await MediaImporter.importItems(items)
        let added = MediaImporter.attach(imported, to: trip)
        try? context.save()
        await MediaImporter.backfillThumbnails(added)
        try? context.save()
    }

    private func remove(_ item: TripMedia) {
        if trip.coverMediaID == item.id { trip.coverMediaID = nil }
        context.delete(item)
        try? context.save()
    }
}
