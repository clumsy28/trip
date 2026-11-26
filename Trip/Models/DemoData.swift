#if DEBUG
import Foundation
import SwiftData
import TripCore

/// Sample trips for previews, screenshots and manual testing (`-seedDemoData`).
enum DemoData {
    private struct Sample {
        let pack: String
        let region: String
        let start: String
        let days: Int
        let title: String
        let notes: String
    }

    private static let samples: [Sample] = [
        .init(pack: "turkey", region: "TR-35", start: "2025-08-12", days: 4, title: "",
              notes: "Kordon'da gün batımı, Alaçatı'da bir gün. Boyoz ve gevrek şart!"),
        .init(pack: "turkey", region: "TR-35", start: "2024-04-20", days: 2, title: "Şirince kaçamağı", notes: ""),
        .init(pack: "turkey", region: "TR-07", start: "2024-07-03", days: 6, title: "Kaş & Kalkan",
              notes: "Kaputaş plajı, Kaş'ta dalış. Meis'e feribot."),
        .init(pack: "turkey", region: "TR-50", start: "2024-10-11", days: 3, title: "Kapadokya balonları",
              notes: "Sabah 5'te kalkıp balonları izledik. Ihlara vadisi yürüyüşü."),
        .init(pack: "turkey", region: "TR-48", start: "2022-07-15", days: 7, title: "Bodrum", notes: ""),
        .init(pack: "turkey", region: "TR-48", start: "2023-08-01", days: 5, title: "Fethiye & Ölüdeniz", notes: ""),
        .init(pack: "turkey", region: "TR-48", start: "2025-06-20", days: 4, title: "Datça", notes: "Knidos'ta gün batımı."),
        .init(pack: "turkey", region: "TR-61", start: "2025-06-02", days: 3, title: "Uzungöl", notes: ""),
        .init(pack: "turkey", region: "TR-53", start: "2025-06-05", days: 2, title: "Ayder yaylası", notes: "Çay bahçeleri!"),
        .init(pack: "turkey", region: "TR-06", start: "2025-03-14", days: 2, title: "", notes: ""),
        .init(pack: "turkey", region: "TR-26", start: "2025-03-16", days: 1, title: "Odunpazarı", notes: ""),
        .init(pack: "turkey", region: "TR-16", start: "2023-02-10", days: 2, title: "Uludağ", notes: ""),
        .init(pack: "turkey", region: "TR-17", start: "2024-05-18", days: 2, title: "Truva & Assos", notes: ""),
        .init(pack: "turkey", region: "TR-47", start: "2025-10-04", days: 3, title: "Mardin", notes: "Taş evler, Midyat."),
        .init(pack: "turkey", region: "TR-27", start: "2025-10-07", days: 2, title: "Gaziantep lezzet turu", notes: ""),
        .init(pack: "turkey", region: "TR-22", start: "2023-11-04", days: 1, title: "Edirne", notes: ""),
        .init(pack: "turkey", region: "TR-41", start: "2024-01-13", days: 1, title: "Kartepe", notes: ""),
        .init(pack: "world", region: "FRA", start: "2024-09-05", days: 5, title: "Paris", notes: ""),
        .init(pack: "world", region: "ITA", start: "2023-05-12", days: 6, title: "Roma & Floransa", notes: ""),
        .init(pack: "world", region: "GRC", start: "2025-09-10", days: 4, title: "Atina", notes: ""),
        .init(pack: "world", region: "JPN", start: "2025-04-01", days: 10, title: "Tokyo & Kyoto", notes: "Sakura zamanı 🌸"),
        .init(pack: "world", region: "DEU", start: "2022-12-10", days: 4, title: "Berlin", notes: ""),
    ]

    static func seed(into context: ModelContext, appState: AppState) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let home = RegionRef(packID: "turkey", regionID: "TR-34")
        appState.homeRegionKey = home.key
        context.markVisited(home)
        for sample in samples {
            guard let start = formatter.date(from: sample.start) else { continue }
            let ref = RegionRef(packID: sample.pack, regionID: sample.region)
            let region = context.markVisited(ref, at: start)
            let end = Calendar.current.date(byAdding: .day, value: sample.days - 1, to: start) ?? start
            let trip = Trip(title: sample.title, startDate: start, endDate: end, notes: sample.notes)
            context.insert(trip)
            trip.region = region
        }
        try? context.save()
    }
}
#endif
