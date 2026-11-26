import Foundation

public struct GroupProgress: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let visited: Int
    public let total: Int
    public var fraction: Double { total == 0 ? 0 : Double(visited) / Double(total) }
}

public struct PackProgress: Sendable, Equatable {
    public let packID: String
    public let visited: Int
    public let total: Int
    public let visitedAreaKm2: Double
    public let totalAreaKm2: Double
    public let groups: [GroupProgress]

    public var fraction: Double { total == 0 ? 0 : Double(visited) / Double(total) }
    public var areaFraction: Double { totalAreaKm2 == 0 ? 0 : visitedAreaKm2 / totalAreaKm2 }
}

public enum ProgressCalculator {
    /// Region IDs of `pack` that should be painted, given every mark the user has across all packs.
    /// A mark in a sub-pack paints its parent region in the containing pack (İstanbul ⇒ Türkiye on the world map).
    public static func effectiveVisited(in pack: MapPack, marks: some Sequence<RegionRef>, allPacks: [MapPack]) -> Set<String> {
        var result = Set<String>()
        var marksByPack: [String: Int] = [:]
        for mark in marks {
            marksByPack[mark.packID, default: 0] += 1
            if mark.packID == pack.id, pack.region(mark.regionID) != nil { result.insert(mark.regionID) }
        }
        for sub in allPacks where sub.id != pack.id {
            if let parent = sub.parentRegionID, marksByPack[sub.id, default: 0] > 0, pack.region(parent) != nil {
                result.insert(parent)
            }
        }
        return result
    }

    public static func progress(of pack: MapPack, visited: Set<String>) -> PackProgress {
        var visitedCount = 0, total = 0
        var visitedArea = 0.0, totalArea = 0.0
        var groupVisited: [String: Int] = [:], groupTotal: [String: Int] = [:]
        for region in pack.regions where region.countsTowardTotal {
            total += 1
            totalArea += region.areaKm2
            groupTotal[region.group, default: 0] += 1
            if visited.contains(region.id) {
                visitedCount += 1
                visitedArea += region.areaKm2
                groupVisited[region.group, default: 0] += 1
            }
        }
        let groups = pack.groups.compactMap { name -> GroupProgress? in
            guard let t = groupTotal[name], t > 0 else { return nil }
            return GroupProgress(name: name, visited: groupVisited[name] ?? 0, total: t)
        }
        return PackProgress(packID: pack.id, visited: visitedCount, total: total,
                            visitedAreaKm2: visitedArea, totalAreaKm2: totalArea, groups: groups)
    }
}

// MARK: - Trip statistics

public struct TripSummary: Sendable, Hashable {
    public let region: RegionRef
    public let regionName: String
    public let start: Date
    public let end: Date
    public let mediaCount: Int

    public init(region: RegionRef, regionName: String, start: Date, end: Date, mediaCount: Int) {
        self.region = region
        self.regionName = regionName
        self.start = start
        self.end = max(start, end)
        self.mediaCount = mediaCount
    }
}

public struct TripStats: Sendable {
    public struct YearCount: Hashable, Sendable, Identifiable {
        public var id: Int { year }
        public let year: Int
        public let trips: Int
        public let days: Int
    }

    public struct RegionCount: Hashable, Sendable {
        public let region: RegionRef
        public let name: String
        public let trips: Int
    }

    public let totalTrips: Int
    /// Distinct calendar days spent on trips (overlapping trips are not double counted).
    public let totalDays: Int
    public let totalMedia: Int
    public let distinctRegions: Int
    public let perYear: [YearCount]
    public let mostVisited: RegionCount?
    public let longestTrip: TripSummary?
    public let latestNewRegion: TripSummary?

    public init(trips: [TripSummary], calendar: Calendar = .current) {
        totalTrips = trips.count
        totalMedia = trips.reduce(0) { $0 + $1.mediaCount }
        distinctRegions = Set(trips.map(\.region)).count

        var allDays = Set<Date>()
        var yearTrips: [Int: Int] = [:]
        var yearDays: [Int: Set<Date>] = [:]
        var longest: (TripSummary, Int)?
        for trip in trips {
            let days = Self.days(of: trip, calendar: calendar)
            allDays.formUnion(days)
            let year = calendar.component(.year, from: trip.start)
            yearTrips[year, default: 0] += 1
            for d in days { yearDays[calendar.component(.year, from: d), default: []].insert(d) }
            if days.count > (longest?.1 ?? 0) { longest = (trip, days.count) }
        }
        totalDays = allDays.count
        longestTrip = longest?.0
        let years = Set(yearTrips.keys).union(yearDays.keys).sorted()
        perYear = years.map { YearCount(year: $0, trips: yearTrips[$0] ?? 0, days: yearDays[$0]?.count ?? 0) }

        var counts: [RegionRef: (String, Int)] = [:]
        for trip in trips { counts[trip.region, default: (trip.regionName, 0)].1 += 1 }
        mostVisited = counts
            .max { a, b in a.value.1 != b.value.1 ? a.value.1 < b.value.1 : a.value.0 > b.value.0 }
            .map { RegionCount(region: $0.key, name: $0.value.0, trips: $0.value.1) }

        // The most recent trip that took the user somewhere for the first time.
        var firstVisit: [RegionRef: TripSummary] = [:]
        for trip in trips.sorted(by: { $0.start < $1.start }) where firstVisit[trip.region] == nil {
            firstVisit[trip.region] = trip
        }
        latestNewRegion = firstVisit.values.max { $0.start < $1.start }
    }

    public static func days(of trip: TripSummary, calendar: Calendar) -> [Date] {
        var day = calendar.startOfDay(for: trip.start)
        let last = calendar.startOfDay(for: trip.end)
        var result: [Date] = []
        while day <= last, result.count < 3660 {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}
