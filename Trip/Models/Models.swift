import Foundation
import SwiftData
import TripCore

// All properties have defaults and relationships are optional so the store can be synced with
// CloudKit later without a migration (CloudKit forbids unique constraints and non-optional relations).

enum TripSource: String, Codable {
    case manual
    case autoImport
}

enum MediaKind: String, Codable {
    case photo
    case video
}

/// A place the user has been to. Its existence is what paints the map.
@Model
final class VisitedRegion {
    /// `packID:regionID`, unique by convention (see `ModelContext.markVisited`).
    var regionKey: String = ""
    var packID: String = ""
    var regionID: String = ""
    var markedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Trip.region)
    var trips: [Trip]? = []

    init(ref: RegionRef, markedAt: Date = .now) {
        regionKey = ref.key
        packID = ref.packID
        regionID = ref.regionID
        self.markedAt = markedAt
    }

    var ref: RegionRef { RegionRef(packID: packID, regionID: regionID) }
    var tripList: [Trip] { (trips ?? []).sorted { $0.startDate > $1.startDate } }
}

/// One dated visit to a place, with notes and media. A place can have many trips.
@Model
final class Trip {
    var id: UUID = UUID()
    var title: String = ""
    var startDate: Date = Date.now
    var endDate: Date = Date.now
    var notes: String = ""
    var sourceRaw: String = TripSource.manual.rawValue
    var coverMediaID: UUID?
    var createdAt: Date = Date.now
    var region: VisitedRegion?

    @Relationship(deleteRule: .cascade, inverse: \TripMedia.trip)
    var media: [TripMedia]? = []

    init(title: String, startDate: Date, endDate: Date, notes: String = "", source: TripSource = .manual) {
        self.title = title
        self.startDate = startDate
        self.endDate = max(startDate, endDate)
        self.notes = notes
        self.sourceRaw = source.rawValue
    }

    var source: TripSource {
        get { TripSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var regionRef: RegionRef? { region?.ref }

    /// Media in capture order.
    var mediaList: [TripMedia] {
        (media ?? []).sorted { ($0.captureDate ?? $0.addedAt, $0.addedAt) < ($1.captureDate ?? $1.addedAt, $1.addedAt) }
    }

    var cover: TripMedia? {
        let list = mediaList
        return list.first { $0.id == coverMediaID } ?? list.first { $0.kind == .photo } ?? list.first
    }

    var dayCount: Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: startDate), to: cal.startOfDay(for: endDate)).day ?? 0
        return max(1, days + 1)
    }
}

/// A photo or video attached to a trip. Normally a reference to the Photos library (no duplicate storage)
/// plus a small cached thumbnail; when the library can't be referenced the image is stored as a copy.
@Model
final class TripMedia {
    var id: UUID = UUID()
    /// `PHAsset.localIdentifier`, nil for copied images.
    var assetIdentifier: String?
    var kindRaw: String = MediaKind.photo.rawValue
    var captureDate: Date?
    var latitude: Double?
    var longitude: Double?
    @Attribute(.externalStorage) var thumbnailData: Data?
    @Attribute(.externalStorage) var imageData: Data?
    var caption: String = ""
    var addedAt: Date = Date.now
    var trip: Trip?

    init(assetIdentifier: String?, kind: MediaKind, captureDate: Date?, location: GeoPoint?, imageData: Data? = nil) {
        self.assetIdentifier = assetIdentifier
        self.kindRaw = kind.rawValue
        self.captureDate = captureDate
        self.latitude = location?.lat
        self.longitude = location?.lon
        self.imageData = imageData
    }

    var kind: MediaKind { MediaKind(rawValue: kindRaw) ?? .photo }
}

// MARK: - Container & helpers

enum AppModelContainer {
    static func make(inMemory: Bool) -> ModelContainer {
        let schema = Schema([VisitedRegion.self, Trip.self, TripMedia.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Could not create the SwiftData container: \(error)")
        }
    }
}

extension ModelContext {
    func visitedRegion(for ref: RegionRef) -> VisitedRegion? {
        let key = ref.key
        var descriptor = FetchDescriptor<VisitedRegion>(predicate: #Predicate { $0.regionKey == key })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    /// Returns the existing mark for `ref` or creates one.
    @discardableResult
    func markVisited(_ ref: RegionRef, at date: Date = .now) -> VisitedRegion {
        if let existing = visitedRegion(for: ref) { return existing }
        let region = VisitedRegion(ref: ref, markedAt: date)
        insert(region)
        return region
    }

    /// Removes the mark and (by cascade) all of its trips.
    func unmark(_ ref: RegionRef) {
        if let region = visitedRegion(for: ref) { delete(region) }
    }

    func trip(id: UUID) -> Trip? {
        var descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    func deleteEverything() {
        try? delete(model: TripMedia.self)
        try? delete(model: Trip.self)
        try? delete(model: VisitedRegion.self)
        try? save()
    }
}
