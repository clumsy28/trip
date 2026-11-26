import Foundation

/// A photo or video from the library, reduced to what the clustering needs.
public struct PhotoSample: Hashable, Sendable {
    public let id: String
    public let date: Date
    public let location: GeoPoint?
    public let isVideo: Bool

    public init(id: String, date: Date, location: GeoPoint?, isVideo: Bool = false) {
        self.id = id
        self.date = date
        self.location = location
        self.isVideo = isVideo
    }
}

/// A trip the user already has, used to avoid duplicate suggestions.
public struct ExistingTrip: Sendable {
    public let id: UUID
    public let region: RegionRef
    public let start: Date
    public let end: Date
    public let assetIDs: Set<String>

    public init(id: UUID, region: RegionRef, start: Date, end: Date, assetIDs: Set<String>) {
        self.id = id
        self.region = region
        self.start = start
        self.end = end
        self.assetIDs = assetIDs
    }
}

public struct ClusterOptions: Sendable, Equatable {
    /// Two photos in the same region belong to the same trip if they are at most this far apart in time.
    public var maxGap: TimeInterval = 48 * 3600
    /// Clusters with fewer photos are treated as "just passing through".
    public var minSamples: Int = 3
    /// Clusters spanning longer than this look like the place the user lives, not a trip.
    public var maxTripDuration: TimeInterval = 30 * 24 * 3600
    /// Slack when matching a cluster to an existing trip's dates.
    public var overlapTolerance: TimeInterval = 24 * 3600
    /// Regions to ignore entirely (the user's home town).
    public var excludedRegions: Set<RegionRef> = []

    public init() {}
}

public struct TripSuggestion: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case newTrip
        /// The cluster overlaps a trip the user already created; offer to add the missing photos to it.
        case addToExisting(tripID: UUID)
    }

    public var id: String { "\(region.key)@\(Int(start.timeIntervalSince1970))" }
    public let region: RegionRef
    public let start: Date
    public let end: Date
    /// Assets to attach, oldest first.
    public let sampleIDs: [String]
    public let kind: Kind
}

public struct TripClusterResult: Sendable {
    public var suggestions: [TripSuggestion]
    /// Regions where photos span weeks continuously — most likely where the user lives.
    public var likelyHomeRegions: [RegionRef]
}

public enum TripClusterer {
    struct Cluster {
        let region: RegionRef
        var samples: [PhotoSample]
        var start: Date { samples.first!.date }
        var end: Date { samples.last!.date }
    }

    /// Groups resolved samples into "stays": per region, time-sorted samples split wherever the gap between
    /// two consecutive photos exceeds `maxGap`. Doing this per region (instead of on the global timeline)
    /// keeps a stay intact when it is interrupted by a day trip to a neighbouring region.
    static func clusters(_ resolved: [(PhotoSample, RegionRef)], maxGap: TimeInterval) -> [Cluster] {
        var byRegion: [RegionRef: [PhotoSample]] = [:]
        for (sample, region) in resolved { byRegion[region, default: []].append(sample) }
        var result: [Cluster] = []
        for (region, samples) in byRegion {
            let sorted = samples.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
            var current = Cluster(region: region, samples: [])
            for s in sorted {
                if let last = current.samples.last, s.date.timeIntervalSince(last.date) > maxGap {
                    result.append(current)
                    current = Cluster(region: region, samples: [])
                }
                current.samples.append(s)
            }
            if !current.samples.isEmpty { result.append(current) }
        }
        return result
    }

    /// Turns library samples into trip suggestions.
    /// - Parameters:
    ///   - samples: photos/videos; ones without a location are ignored.
    ///   - resolve: maps a coordinate to a region (see `RegionResolver`).
    ///   - existing: trips the user already has.
    public static func suggest(samples: [PhotoSample],
                               existing: [ExistingTrip],
                               options: ClusterOptions = ClusterOptions(),
                               resolve: (GeoPoint) -> RegionRef?) -> TripClusterResult {
        let attached = existing.reduce(into: Set<String>()) { $0.formUnion($1.assetIDs) }
        var resolved: [(PhotoSample, RegionRef)] = []
        for sample in samples where !attached.contains(sample.id) {
            guard let location = sample.location, let region = resolve(location),
                  !options.excludedRegions.contains(region) else { continue }
            resolved.append((sample, region))
        }

        var suggestions: [TripSuggestion] = []
        var likelyHome = Set<RegionRef>()
        for cluster in clusters(resolved, maxGap: options.maxGap) {
            guard cluster.samples.count >= options.minSamples else { continue }
            if cluster.end.timeIntervalSince(cluster.start) > options.maxTripDuration {
                likelyHome.insert(cluster.region)
                continue
            }
            let ids = cluster.samples.map(\.id)
            let overlapping = existing.first { trip in
                trip.region == cluster.region
                    && cluster.start <= trip.end.addingTimeInterval(options.overlapTolerance)
                    && cluster.end >= trip.start.addingTimeInterval(-options.overlapTolerance)
            }
            let kind: TripSuggestion.Kind = overlapping.map { .addToExisting(tripID: $0.id) } ?? .newTrip
            suggestions.append(TripSuggestion(region: cluster.region, start: cluster.start, end: cluster.end,
                                              sampleIDs: ids, kind: kind))
        }
        suggestions.sort { $0.start > $1.start }
        return TripClusterResult(suggestions: suggestions,
                                 likelyHomeRegions: likelyHome.sorted { $0.key < $1.key })
    }

    /// For "create a trip from these photos": the region most photos were taken in, and their date span.
    public static func infer(from samples: [PhotoSample],
                             resolve: (GeoPoint) -> RegionRef?) -> (region: RegionRef?, start: Date, end: Date)? {
        guard let first = samples.min(by: { $0.date < $1.date }),
              let last = samples.max(by: { $0.date < $1.date }) else { return nil }
        var votes: [RegionRef: Int] = [:]
        for s in samples {
            if let loc = s.location, let r = resolve(loc) { votes[r, default: 0] += 1 }
        }
        let region = votes.max { a, b in a.value != b.value ? a.value < b.value : a.key.key > b.key.key }?.key
        return (region, first.date, last.date)
    }
}
