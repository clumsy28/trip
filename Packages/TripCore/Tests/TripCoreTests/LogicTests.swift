import Foundation
import Testing
@testable import TripCore

private let istanbul = RegionRef(packID: "turkey", regionID: "TR-34")
private let izmir = RegionRef(packID: "turkey", regionID: "TR-35")
private let manisa = RegionRef(packID: "turkey", regionID: "TR-45")
private let paris = RegionRef(packID: "world", regionID: "FRA")

private let base = ISO8601DateFormatter().date(from: "2025-08-01T10:00:00Z")!
private func at(days: Double, hours: Double = 0) -> Date { base.addingTimeInterval(days * 86400 + hours * 3600) }

/// Fake coordinates: each region gets its own longitude so the fake resolver can map them back.
private let fakeCoords: [RegionRef: GeoPoint] = [
    istanbul: GeoPoint(lon: 1, lat: 0), izmir: GeoPoint(lon: 2, lat: 0),
    manisa: GeoPoint(lon: 3, lat: 0), paris: GeoPoint(lon: 4, lat: 0),
]
private func fakeResolve(_ p: GeoPoint) -> RegionRef? { fakeCoords.first { $0.value == p }?.key }

private func photos(_ region: RegionRef, _ prefix: String, count: Int, startDay: Double, everyHours: Double = 3) -> [PhotoSample] {
    (0..<count).map { i in
        PhotoSample(id: "\(prefix)-\(i)", date: at(days: startDay, hours: Double(i) * everyHours), location: fakeCoords[region])
    }
}

@Suite("Trip clustering")
struct ClustererTests {
    @Test func twoVisitsMonthsApartBecomeTwoTrips() {
        let samples = photos(izmir, "a", count: 10, startDay: 0) + photos(izmir, "b", count: 6, startDay: 120)
        let result = TripClusterer.suggest(samples: samples, existing: [], resolve: fakeResolve)
        #expect(result.suggestions.count == 2)
        #expect(result.suggestions.allSatisfy { $0.region == izmir && $0.kind == .newTrip })
        #expect(result.suggestions[0].sampleIDs.first == "b-0") // newest first
        #expect(result.suggestions[1].sampleIDs.count == 10)
    }

    @Test func passingThroughIsIgnoredAndDayTripDoesNotSplitAStay() {
        // İzmir for 4 days, with a 2-photo stop in Manisa in the middle.
        var samples = photos(izmir, "iz", count: 12, startDay: 0, everyHours: 8)
        samples += photos(manisa, "ma", count: 2, startDay: 1.5, everyHours: 1)
        let result = TripClusterer.suggest(samples: samples, existing: [], resolve: fakeResolve)
        #expect(result.suggestions.count == 1)
        #expect(result.suggestions[0].region == izmir)
        #expect(result.suggestions[0].sampleIDs.count == 12)
    }

    @Test func gapLongerThanTwoDaysSplits() {
        let samples = photos(paris, "p1", count: 4, startDay: 0) + photos(paris, "p2", count: 4, startDay: 3)
        let result = TripClusterer.suggest(samples: samples, existing: [], resolve: fakeResolve)
        #expect(result.suggestions.count == 2)
    }

    @Test func homeRegionIsExcludedAndLongStaysAreFlaggedAsHome() {
        var options = ClusterOptions()
        options.excludedRegions = [istanbul]
        let daily = (0..<60).map { PhotoSample(id: "ist-\($0)", date: at(days: Double($0)), location: fakeCoords[istanbul]) }
        let parisDaily = (0..<60).map { PhotoSample(id: "par-\($0)", date: at(days: Double($0)), location: fakeCoords[paris]) }
        let excluded = TripClusterer.suggest(samples: daily, existing: [], options: options, resolve: fakeResolve)
        #expect(excluded.suggestions.isEmpty)
        #expect(excluded.likelyHomeRegions.isEmpty)
        let flagged = TripClusterer.suggest(samples: parisDaily, existing: [], resolve: fakeResolve)
        #expect(flagged.suggestions.isEmpty)
        #expect(flagged.likelyHomeRegions == [paris])
    }

    @Test func overlappingExistingTripGetsOnlyNewPhotos() {
        let samples = photos(izmir, "x", count: 6, startDay: 0)
        let trip = ExistingTrip(id: UUID(), region: izmir, start: at(days: 0), end: at(days: 1),
                                assetIDs: ["x-0", "x-1", "x-2"])
        let result = TripClusterer.suggest(samples: samples, existing: [trip], resolve: fakeResolve)
        #expect(result.suggestions.count == 1)
        #expect(result.suggestions[0].kind == .addToExisting(tripID: trip.id))
        #expect(result.suggestions[0].sampleIDs == ["x-3", "x-4", "x-5"])
    }

    @Test func fullyImportedTripProducesNoSuggestion() {
        let samples = photos(izmir, "x", count: 4, startDay: 0)
        let trip = ExistingTrip(id: UUID(), region: izmir, start: at(days: 0), end: at(days: 1),
                                assetIDs: Set(samples.map(\.id)))
        #expect(TripClusterer.suggest(samples: samples, existing: [trip], resolve: fakeResolve).suggestions.isEmpty)
    }

    @Test func photosWithoutLocationAreIgnored() {
        let samples = (0..<5).map { PhotoSample(id: "n\($0)", date: at(days: 0, hours: Double($0)), location: nil) }
        #expect(TripClusterer.suggest(samples: samples, existing: [], resolve: fakeResolve).suggestions.isEmpty)
    }

    @Test func inferPicksMajorityRegionAndDateSpan() {
        let samples = photos(izmir, "i", count: 3, startDay: 0) + photos(manisa, "m", count: 1, startDay: 2)
            + [PhotoSample(id: "noloc", date: at(days: 5), location: nil)]
        let inferred = TripClusterer.infer(from: samples, resolve: fakeResolve)
        #expect(inferred?.region == izmir)
        #expect(inferred?.start == at(days: 0))
        #expect(inferred?.end == at(days: 5))
    }
}

@Suite("Progress & stats")
struct ProgressTests {
    @Test func provinceMarkPaintsCountryOnWorldMap() {
        let packs = [Fixtures.turkey, Fixtures.world]
        let marks = [istanbul, paris]
        #expect(ProgressCalculator.effectiveVisited(in: Fixtures.world, marks: marks, allPacks: packs) == ["TUR", "FRA"])
        #expect(ProgressCalculator.effectiveVisited(in: Fixtures.turkey, marks: marks, allPacks: packs) == ["TR-34"])
    }

    @Test func progressCountsAndGroups() {
        let p = ProgressCalculator.progress(of: Fixtures.turkey, visited: ["TR-34", "TR-35", "TR-45", "TR-06"])
        #expect(p.visited == 4)
        #expect(p.total == 81)
        #expect(abs(p.fraction - 4.0 / 81.0) < 1e-9)
        #expect(p.groups.count == 7)
        #expect(p.groups.first { $0.name == "Ege" }?.visited == 2)
        #expect(p.groups.first { $0.name == "Marmara" }?.visited == 1)
        #expect(p.areaFraction > 0 && p.areaFraction < 1)
    }

    @Test func tripStats() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let trips = [
            TripSummary(region: izmir, regionName: "İzmir", start: at(days: 0), end: at(days: 2), mediaCount: 10),
            TripSummary(region: izmir, regionName: "İzmir", start: at(days: 200), end: at(days: 200), mediaCount: 3),
            TripSummary(region: paris, regionName: "Fransa", start: at(days: 1), end: at(days: 7), mediaCount: 5),
        ]
        let stats = TripStats(trips: trips, calendar: cal)
        #expect(stats.totalTrips == 3)
        #expect(stats.totalMedia == 18)
        #expect(stats.distinctRegions == 2)
        #expect(stats.totalDays == 9) // days 0–7 overlap-merged (8) + day 200
        #expect(stats.mostVisited?.region == izmir)
        #expect(stats.mostVisited?.trips == 2)
        #expect(stats.longestTrip?.region == paris)
        #expect(stats.latestNewRegion?.region == paris)
        #expect(stats.perYear.map(\.year) == [2025, 2026])
    }
}
