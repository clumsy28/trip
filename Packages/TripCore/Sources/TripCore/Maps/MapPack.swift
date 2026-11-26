import Foundation

/// One selectable area on a map: a province of Türkiye, a country of the world, …
public struct MapRegion: Identifiable, Sendable {
    public let id: String
    public let name: String
    /// Geographic region (for provinces) or continent (for countries).
    public let group: String
    /// Whether the region is part of the "% visited" denominator.
    public let countsTowardTotal: Bool
    public let areaKm2: Double
    public let label: GeoPoint
    /// Geographic bounds (x = lon, y = lat).
    public let bbox: BoundingBox
    /// All rings of all parts; rendered and hit-tested with the even-odd rule.
    public let rings: [[GeoPoint]]

    public init(id: String, name: String, group: String, countsTowardTotal: Bool, areaKm2: Double,
                label: GeoPoint, bbox: BoundingBox, rings: [[GeoPoint]]) {
        self.id = id
        self.name = name
        self.group = group
        self.countsTowardTotal = countsTowardTotal
        self.areaKm2 = areaKm2
        self.label = label
        self.bbox = bbox
        self.rings = rings
    }

    public func contains(_ p: GeoPoint) -> Bool {
        bbox.contains(x: p.lon, y: p.lat) && PolygonMath.contains(x: p.lon, y: p.lat, rings: rings)
    }

    /// Approximate distance in km from `p` to the region's outline (0 when inside).
    public func distanceKm(to p: GeoPoint) -> Double {
        if contains(p) { return 0 }
        let kx = cos(p.lat * .pi / 180) * 111.32, ky = 110.57
        var best = Double.infinity
        for ring in rings where ring.count >= 2 {
            var prev = ring[ring.count - 1]
            for cur in ring {
                let d = PolygonMath.distanceSquared(
                    px: p.lon * kx, py: p.lat * ky,
                    ax: prev.lon * kx, ay: prev.lat * ky,
                    bx: cur.lon * kx, by: cur.lat * ky)
                best = min(best, d)
                prev = cur
            }
        }
        return best.squareRoot()
    }
}

extension MapRegion: Hashable {
    public static func == (a: MapRegion, b: MapRegion) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

/// A selectable map ("Türkiye – 81 il", "Dünya – ülkeler"). Adding a new map is just adding a pack file.
public struct MapPack: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let version: Int
    public let projection: ProjectionKind
    /// The region of the world pack this pack subdivides ("TUR" for Türkiye), if any.
    public let parentRegionID: String?
    /// "Bölge" / "Kıta"
    public let groupTitle: String
    public let groups: [String]
    public let regions: [MapRegion]
    private let indexByID: [String: Int]

    public init(id: String, name: String, version: Int, projection: ProjectionKind, parentRegionID: String?,
                groupTitle: String, groups: [String], regions: [MapRegion]) {
        self.id = id
        self.name = name
        self.version = version
        self.projection = projection
        self.parentRegionID = parentRegionID
        self.groupTitle = groupTitle
        self.groups = groups
        self.regions = regions
        var index: [String: Int] = [:]
        for (i, r) in regions.enumerated() { index[r.id] = i }
        self.indexByID = index
    }

    public func region(_ id: String) -> MapRegion? {
        indexByID[id].map { regions[$0] }
    }

    public var countedRegions: [MapRegion] { regions.filter(\.countsTowardTotal) }

    // MARK: Decoding

    private struct DTO: Decodable {
        struct Region: Decodable {
            let id: String
            let name: String
            let group: String
            let countsTowardTotal: Bool
            let areaKm2: Double
            let label: [Double]
            let bbox: [Double]
            let polygons: [[[Double]]]
        }
        let id: String
        let name: String
        let version: Int
        let projection: ProjectionKind
        let parentRegionID: String?
        let groupTitle: String
        let groups: [String]
        let regions: [Region]
    }

    public enum DecodingError: Error, Equatable {
        case malformedRegion(String)
    }

    public static func decode(from data: Data) throws -> MapPack {
        let dto = try JSONDecoder().decode(DTO.self, from: data)
        let regions = try dto.regions.map { r -> MapRegion in
            guard r.label.count == 2, r.bbox.count == 4 else { throw DecodingError.malformedRegion(r.id) }
            var rings: [[GeoPoint]] = []
            for polygon in r.polygons {
                for flat in polygon {
                    guard flat.count >= 6, flat.count.isMultiple(of: 2) else { throw DecodingError.malformedRegion(r.id) }
                    var ring: [GeoPoint] = []
                    ring.reserveCapacity(flat.count / 2)
                    var i = 0
                    while i < flat.count {
                        ring.append(GeoPoint(lon: flat[i], lat: flat[i + 1]))
                        i += 2
                    }
                    rings.append(ring)
                }
            }
            return MapRegion(
                id: r.id, name: r.name, group: r.group, countsTowardTotal: r.countsTowardTotal,
                areaKm2: r.areaKm2, label: GeoPoint(lon: r.label[0], lat: r.label[1]),
                bbox: BoundingBox(minX: r.bbox[0], minY: r.bbox[1], maxX: r.bbox[2], maxY: r.bbox[3]),
                rings: rings)
        }
        return MapPack(id: dto.id, name: dto.name, version: dto.version, projection: dto.projection,
                       parentRegionID: dto.parentRegionID, groupTitle: dto.groupTitle, groups: dto.groups,
                       regions: regions)
    }
}

/// A reference to a region inside a specific pack, e.g. `turkey:TR-34`.
public struct RegionRef: Hashable, Sendable, Codable, CustomStringConvertible {
    public let packID: String
    public let regionID: String

    public init(packID: String, regionID: String) {
        self.packID = packID
        self.regionID = regionID
    }

    /// Stable string form, used as the persisted key.
    public var key: String { "\(packID):\(regionID)" }

    public init?(key: String) {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        self.init(packID: parts[0], regionID: parts[1])
    }

    public var description: String { key }
}
