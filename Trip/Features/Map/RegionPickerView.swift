import SwiftData
import SwiftUI
import TripCore

/// Searchable list of regions from one or more packs (Turkish-aware matching: "mugla" finds "Muğla").
struct RegionPickerView: View {
    let packIDs: [String]
    var title = "Yer seç"
    let onPick: (RegionRef) -> Void

    @Environment(MapPackStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Query private var marks: [VisitedRegion]
    @State private var query = ""

    var body: some View {
        let visited = Set(marks.map(\.regionKey))
        NavigationStack {
            List {
                ForEach(packIDs.compactMap(store.pack)) { pack in
                    let regions = filtered(pack)
                    if !regions.isEmpty {
                        Section(packIDs.count > 1 ? pack.name : "") {
                            ForEach(regions) { region in
                                let ref = RegionRef(packID: pack.id, regionID: region.id)
                                Button {
                                    onPick(ref)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(region.name)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(region.group)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if visited.contains(ref.key) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Theme.accent)
                                        }
                                    }
                                }
                                .accessibilityIdentifier("region.\(region.id)")
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "İl veya ülke ara")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
        }
    }

    private func filtered(_ pack: MapPack) -> [MapRegion] {
        let key = query.trimmingCharacters(in: .whitespaces).searchKey
        return pack.regions
            .filter { key.isEmpty || $0.name.searchKey.contains(key) }
            .sorted { $0.name.turkishCompare($1.name) == .orderedAscending }
    }
}
