import Foundation
import Testing
@testable import TripCore

enum Fixtures {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // TripCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // TripCore
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repo root

    static func pack(_ name: String) throws -> MapPack {
        let url = repoRoot.appendingPathComponent("Trip/Resources/MapPacks/\(name).json")
        return try MapPack.decode(from: Data(contentsOf: url))
    }

    static let turkey = try! pack("turkey")
    static let world = try! pack("world")
}

@Suite("Projections")
struct ProjectionTests {
    @Test(arguments: [ProjectionKind.mercator, .equalEarth])
    func roundTrip(kind: ProjectionKind) {
        let projection = kind.projection
        for p in [GeoPoint(lon: 28.97, lat: 41.01), GeoPoint(lon: -122.4, lat: 37.77),
                  GeoPoint(lon: 151.2, lat: -33.86), GeoPoint(lon: 0, lat: 0)] {
            let back = projection.unproject(projection.project(p))
            #expect(abs(back.lon - p.lon) < 1e-6)
            #expect(abs(back.lat - p.lat) < 1e-6)
        }
    }

    @Test func equalEarthKeepsNorthUp() {
        let p = EqualEarthProjection()
        #expect(p.project(GeoPoint(lon: 0, lat: 60)).y > p.project(GeoPoint(lon: 0, lat: 10)).y)
        #expect(p.project(GeoPoint(lon: 90, lat: 0)).x > 0)
    }
}

@Suite("Map packs")
struct MapPackTests {
    @Test func turkeyHas81Provinces() {
        let pack = Fixtures.turkey
        #expect(pack.regions.count == 81)
        #expect(pack.parentRegionID == "TUR")
        #expect(pack.region("TR-34")?.name == "İstanbul")
        #expect(pack.region("TR-35")?.group == "Ege")
        #expect(Set(pack.regions.map(\.group)) == Set(pack.groups))
        let totalArea = pack.regions.reduce(0) { $0 + $1.areaKm2 }
        #expect(totalArea > 740_000 && totalArea < 820_000) // Türkiye ≈ 783 562 km²
    }

    @Test func worldCountsUNStates() {
        let pack = Fixtures.world
        #expect(pack.countedRegions.count == 195)
        #expect(pack.region("TUR")?.name == "Türkiye")
        #expect(pack.region("FRA") != nil)
    }

    @Test func polygonContainsHolesWithEvenOdd() {
        let outer = [GeoPoint(lon: 0, lat: 0), GeoPoint(lon: 10, lat: 0), GeoPoint(lon: 10, lat: 10), GeoPoint(lon: 0, lat: 10)]
        let hole = [GeoPoint(lon: 4, lat: 4), GeoPoint(lon: 6, lat: 4), GeoPoint(lon: 6, lat: 6), GeoPoint(lon: 4, lat: 6)]
        #expect(PolygonMath.contains(x: 2, y: 2, rings: [outer, hole]))
        #expect(!PolygonMath.contains(x: 5, y: 5, rings: [outer, hole]))
        #expect(!PolygonMath.contains(x: 12, y: 5, rings: [outer, hole]))
    }

    @Test func regionRefKeyRoundTrip() {
        let ref = RegionRef(packID: "turkey", regionID: "TR-34")
        #expect(ref.key == "turkey:TR-34")
        #expect(RegionRef(key: ref.key) == ref)
        #expect(RegionRef(key: "garbage") == nil)
    }
}

@Suite("Offline reverse geocoding")
struct ResolverTests {
    let resolver = RegionResolver(packs: [Fixtures.turkey, Fixtures.world])

    @Test(arguments: [
        (41.0082, 28.9784, "turkey:TR-34"), // İstanbul, Sultanahmet
        (40.9903, 29.0290, "turkey:TR-34"), // Kadıköy (coast)
        (39.9334, 32.8597, "turkey:TR-06"), // Ankara
        (38.4237, 27.1428, "turkey:TR-35"), // İzmir (coast)
        (36.8969, 30.7133, "turkey:TR-07"), // Antalya (coast)
        (38.6431, 34.8289, "turkey:TR-50"), // Göreme, Nevşehir
        (37.0344, 27.4305, "turkey:TR-48"), // Bodrum
        (48.8566, 2.3522, "world:FRA"),     // Paris
        (41.9028, 12.4964, "world:ITA"),    // Roma
        (35.6762, 139.6503, "world:JPN"),   // Tokyo
        (40.7128, -74.0060, "world:USA"),   // New York
    ])
    func resolves(lat: Double, lon: Double, expected: String) {
        #expect(resolver.resolve(GeoPoint(lon: lon, lat: lat))?.key == expected)
    }

    @Test func openSeaResolvesToNothing() {
        #expect(resolver.resolve(GeoPoint(lon: 18.0, lat: 35.0)) == nil)
        #expect(resolver.resolve(GeoPoint(lon: -40.0, lat: 30.0)) == nil)
    }
}

@Suite("Projected map hit testing")
struct ProjectedMapTests {
    @Test func tappingAProvinceLabelHitsThatProvince() {
        let pack = Fixtures.turkey
        let map = ProjectedMap(pack: pack)
        #expect(map.aspectRatio > 2) // Türkiye is wide
        for id in ["TR-34", "TR-06", "TR-35", "TR-65", "TR-77"] {
            let region = map.regions.first { $0.id == id }!
            #expect(map.hitTest(x: region.label.x, y: region.label.y) == id, "label of \(id)")
        }
        #expect(map.hitTest(x: -1, y: -1) == nil)
    }

    @Test func toleranceSnapsToNearestCoast() {
        let map = ProjectedMap(pack: Fixtures.turkey)
        // In the Black Sea, a few km off Kilyos (İstanbul).
        let p = map.unitPoint(for: GeoPoint(lon: 29.10, lat: 41.30))
        #expect(map.hitTest(x: p.x, y: p.y) == nil)
        #expect(map.hitTest(x: p.x, y: p.y, tolerance: 0.02) == "TR-34")
        // Unit space round trip for a land point.
        let ankara = map.unitPoint(for: GeoPoint(lon: 32.86, lat: 39.93))
        #expect(map.hitTest(x: ankara.x, y: ankara.y) == "TR-06")
    }
}
