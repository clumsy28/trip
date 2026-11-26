import Charts
import SwiftData
import SwiftUI
import TripCore

struct StatsScreen: View {
    @Environment(AppState.self) private var app
    @Environment(MapPackStore.self) private var store
    @Query private var marks: [VisitedRegion]
    @Query(sort: \Trip.startDate) private var trips: [Trip]
    @State private var byArea = false

    var body: some View {
        @Bindable var app = app
        let pack = store.pack(app.selectedPackID) ?? store.packs[0]
        let visited = ProgressCalculator.effectiveVisited(in: pack, marks: marks.map(\.ref), allPacks: store.packs)
        let progress = ProgressCalculator.progress(of: pack, visited: visited)
        let stats = TripStats(trips: trips.compactMap { trip in
            trip.regionRef.map {
                TripSummary(region: $0, regionName: store.name(of: $0), start: trip.startDate, end: trip.endDate,
                            mediaCount: trip.media?.count ?? 0)
            }
        })

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Harita", selection: $app.selectedPackID.animation()) {
                        ForEach(store.packs) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.segmented)

                    heroCard(pack: pack, progress: progress)
                    groupCard(pack: pack, progress: progress)

                    if stats.totalTrips > 0 {
                        highlights(stats)
                        yearlyCard(stats)
                    } else {
                        ContentUnavailableView("Grafikler seni bekliyor",
                                               systemImage: "chart.bar.xaxis",
                                               description: Text("İlk gezini eklediğinde burada yıllara göre gezilerini ve en çok gittiğin yerleri göreceksin."))
                            .card()
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("İstatistik")
        }
    }

    // MARK: Cards

    private func heroCard(pack: MapPack, progress: PackProgress) -> some View {
        let fraction = byArea ? progress.areaFraction : progress.fraction
        return VStack(spacing: 16) {
            HStack(spacing: 20) {
                ZStack {
                    ProgressRing(fraction: fraction, lineWidth: 16)
                    VStack(spacing: 0) {
                        Text(Format.percent(fraction))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text(byArea ? "alan" : pack.unitName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 130, height: 130)
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 6) {
                    Text(pack.name)
                        .font(.title2.weight(.bold))
                    if byArea {
                        Text("\(Format.number(Int(progress.visitedAreaKm2))) km² / \(Format.number(Int(progress.totalAreaKm2))) km²")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(progress.total) \(pack.unitName)den \(progress.visited) \(pack.unitName) gezildi")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    let remaining = progress.total - progress.visited
                    if remaining > 0 && !byArea {
                        Text("Keşfedilecek \(remaining) \(pack.unitName) daha var ✨")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            Picker("Ölçü", selection: $byArea.animation(.snappy)) {
                Text("\(pack.unitName.capitalized(with: Format.locale)) sayısı").tag(false)
                Text("Yüzölçümü").tag(true)
            }
            .pickerStyle(.segmented)
        }
        .card()
    }

    private func groupCard(pack: MapPack, progress: PackProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pack.groupTitle == "Kıta" ? "Kıtalara göre" : "Bölgelere göre")
                .font(.headline)
            Chart(progress.groups) { group in
                BarMark(xStart: .value("Başlangıç", 0), xEnd: .value("Tamamı", 1), y: .value("Grup", group.name),
                        height: .fixed(12))
                    .foregroundStyle(Theme.placeholder)
                    .clipShape(Capsule())
                    .annotation(position: .trailing, alignment: .leading, spacing: 8) {
                        Text("\(group.visited)/\(group.total)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                if group.visited > 0 {
                    BarMark(xStart: .value("Başlangıç", 0), xEnd: .value("Oran", max(group.fraction, 0.03)),
                            y: .value("Grup", group.name), height: .fixed(12))
                        .foregroundStyle(Theme.barGradient)
                        .clipShape(Capsule())
                }
            }
            .chartXScale(domain: 0...1.15)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { _ in AxisValueLabel().font(.caption) }
            }
            .frame(height: CGFloat(progress.groups.count) * 34)
        }
        .card()
    }

    private func highlights(_ stats: TripStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(systemImage: "suitcase.fill", value: Format.number(stats.totalTrips), label: "Gezi")
            StatTile(systemImage: "sun.max.fill", value: Format.number(stats.totalDays), label: "Yolda geçen gün",
                     tint: .orange)
            StatTile(systemImage: "mappin.and.ellipse", value: Format.number(stats.distinctRegions), label: "Farklı yer",
                     tint: Theme.home)
            StatTile(systemImage: "photo.stack.fill", value: Format.number(stats.totalMedia), label: "Fotoğraf ve video",
                     tint: .purple)
            if let most = stats.mostVisited {
                StatTile(systemImage: "heart.fill", value: most.name, label: "En çok gidilen · \(most.trips) gezi",
                         tint: .pink)
            }
            if let longest = stats.longestTrip {
                let days = TripStats.days(of: longest, calendar: .current).count
                StatTile(systemImage: "hourglass", value: longest.regionName, label: "En uzun gezi · \(days) gün",
                         tint: .teal)
            }
            if let latest = stats.latestNewRegion {
                StatTile(systemImage: "sparkles", value: latest.regionName,
                         label: "Son keşif · \(Format.monthYear(latest.start))", tint: .yellow)
            }
        }
    }

    private func yearlyCard(_ stats: TripStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Yıllara göre geziler")
                .font(.headline)
            Chart(stats.perYear) { year in
                BarMark(x: .value("Yıl", String(year.year)), y: .value("Gezi", year.trips))
                    .foregroundStyle(Theme.barGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .annotation(position: .top) {
                        Text("\(year.trips)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
            }
            .chartYAxis(.hidden)
            .frame(height: 180)
            Text("Toplam \(stats.perYear.reduce(0) { $0 + $1.days }) gün yoldaydın.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }
}

