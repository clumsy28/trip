import Photos
import SwiftData
import SwiftUI
import TripCore

struct SettingsScreen: View {
    @Environment(AppState.self) private var app
    @Environment(MapPackStore.self) private var store
    @Environment(\.modelContext) private var context
    @State private var showHomePicker = false
    @State private var confirmReset = false
    @State private var photoStatus = PhotoLibrary.status

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Form {
                Section {
                    Button {
                        showHomePicker = true
                    } label: {
                        HStack {
                            Label("Memleketim", systemImage: "house.fill")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(app.homeRegion.map { store.fullName(of: $0) } ?? "Seçilmedi")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if app.homeRegion != nil {
                        Button("Memleketi kaldır", role: .destructive) { app.homeRegionKey = nil }
                    }
                } header: {
                    Text("Yaşadığın yer")
                } footer: {
                    Text("Memleketin haritada mavi görünür ve otomatik gezi önerilerine dahil edilmez.")
                }

                Section("Otomatik gezi bulma") {
                    Toggle("Memleketimdeki fotoğrafları da dahil et", isOn: $app.includeHomeInAutoImport)
                    Button {
                        app.isAutoImportPresented = true
                    } label: {
                        Label("Fotoğraflarımdan gezileri bul", systemImage: "sparkles")
                    }
                }

                Section("Galeri erişimi") {
                    HStack {
                        Text("Durum")
                        Spacer()
                        Text(statusText).foregroundStyle(.secondary)
                    }
                    if photoStatus == .notDetermined {
                        Button("İzin ver") {
                            Task { photoStatus = await PhotoLibrary.requestAccess() }
                        }
                    } else {
                        Button("Ayarlarda değiştir") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }

                Section("Veriler") {
                    Button("Tüm gezileri ve işaretleri sil", role: .destructive) { confirmReset = true }
                    #if DEBUG
                    Button("Demo verisi yükle") { DemoData.seed(into: context, appState: app) }
                    #endif
                }

                Section("Hakkında") {
                    LabeledContent("Sürüm", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                    Link(destination: URL(string: "https://github.com/clumsy28/trip")!) {
                        Label("Kaynak kod (GitHub)", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Text("Harita sınırları Natural Earth verisinden üretilmiştir (public domain). Fotoğrafların cihazından dışarı çıkmaz.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ayarlar")
            .onAppear { photoStatus = PhotoLibrary.status }
            .sheet(isPresented: $showHomePicker) {
                RegionPickerView(packIDs: MapPackStore.bundledPackIDs, title: "Nerede yaşıyorsun?") { ref in
                    app.homeRegionKey = ref.key
                    context.markVisited(ref)
                    try? context.save()
                }
            }
            .confirmationDialog("Her şey silinsin mi?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Tümünü sil", role: .destructive) {
                    context.deleteEverything()
                    app.homeRegionKey = nil
                }
            } message: {
                Text("Tüm geziler, notlar ve işaretler silinir. Galerindeki fotoğraflar etkilenmez.")
            }
        }
    }

    private var statusText: String {
        switch photoStatus {
        case .authorized: "Tam erişim"
        case .limited: "Sınırlı erişim"
        case .denied: "Kapalı"
        case .restricted: "Kısıtlı"
        case .notDetermined: "Sorulmadı"
        @unknown default: "Bilinmiyor"
        }
    }
}

struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @Environment(MapPackStore.self) private var store
    @Environment(\.modelContext) private var context
    @State private var home: RegionRef?
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)
            Image("AppIconPreview")
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Theme.accent.opacity(0.35), radius: 16, y: 8)
            VStack(spacing: 8) {
                Text("Trip'e hoş geldin")
                    .font(.largeTitle.weight(.bold))
                Text("Gezdiğin yerleri haritada boya, anılarını şehir şehir sakla.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 18) {
                feature("map.fill", "Haritanı boya", "Türkiye'nin 81 ili ya da dünya ülkeleri. Gittikçe harita renklenir.")
                feature("photo.on.rectangle.angled", "Anılarını ekle", "Her gezine fotoğraf, video ve notlar iliştir.")
                feature("sparkles", "Otomatik bul", "Fotoğraflarının konum ve tarihinden gezilerini çıkaralım.")
                feature("chart.pie.fill", "İlerlemeni gör", "Hangi bölgenin yüzde kaçını gezdiğini grafiklerle izle.")
            }
            .padding(.horizontal, 8)
            Spacer(minLength: 12)
            VStack(spacing: 12) {
                Button {
                    showPicker = true
                } label: {
                    HStack {
                        Image(systemName: "house.fill")
                        Text(home.map { "Memleketim: \(store.name(of: $0))" } ?? "Nerede yaşıyorsun? (isteğe bağlı)")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)

                Button {
                    if let home {
                        app.homeRegionKey = home.key
                        context.markVisited(home)
                        try? context.save()
                    }
                    app.hasCompletedOnboarding = true
                } label: {
                    Text("Başla")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("onboarding.start")
            }
        }
        .padding(28)
        .sheet(isPresented: $showPicker) {
            RegionPickerView(packIDs: MapPackStore.bundledPackIDs, title: "Nerede yaşıyorsun?") { home = $0 }
        }
    }

    private func feature(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
