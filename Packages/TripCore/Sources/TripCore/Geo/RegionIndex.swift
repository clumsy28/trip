import Foundation

/// Grid-based spatial index over a pack's geographic bounding boxes for fast point lookups.
public struct RegionIndex: Sendable {
    public let pack: MapPack
    private let cellSize: Double
    private let cells: [Int: [Int]]

    public init(pack: MapPack, cellSize: Double = 1.0) {
        self.pack = pack
        self.cellSize = cellSize
        var cells: [Int: [Int]] = [:]
        for (i, region) in pack.regions.enumerated() {
            let b = region.bbox
            for cx in Self.cell(b.minX, cellSize, 180)...Self.cell(b.maxX, cellSize, 180) {
                for cy in Self.cell(b.minY, cellSize, 90)...Self.cell(b.maxY, cellSize, 90) {
                    cells[Self.key(cx, cy), default: []].append(i)
                }
            }
        }
        self.cells = cells
    }

    private static func cell(_ v: Double, _ size: Double, _ offset: Double) -> Int {
        Int(((v + offset) / size).rounded(.down))
    }

    private static func key(_ cx: Int, _ cy: Int) -> Int { cx * 100_000 + cy }

    /// The region strictly containing `p`.
    public func region(containing p: GeoPoint) -> MapRegion? {
        let k = Self.key(Self.cell(p.lon, cellSize, 180), Self.cell(p.lat, cellSize, 90))
        for i in cells[k] ?? [] where pack.regions[i].contains(p) {
            return pack.regions[i]
        }
        return nil
    }

    /// The nearest region whose outline is within `maxDistanceKm` of `p` (e.g. a photo taken on a boat or
    /// on a coastline that the simplified geometry cuts off).
    public func nearestRegion(to p: GeoPoint, maxDistanceKm: Double) -> (region: MapRegion, distanceKm: Double)? {
        let degLat = maxDistanceKm / 110.57
        let degLon = maxDistanceKm / max(1, cos(p.lat * .pi / 180) * 111.32)
        var best: (MapRegion, Double)?
        for region in pack.regions {
            let b = region.bbox
            guard p.lon >= b.minX - degLon, p.lon <= b.maxX + degLon,
                  p.lat >= b.minY - degLat, p.lat <= b.maxY + degLat else { continue }
            let d = region.distanceKm(to: p)
            if d <= maxDistanceKm, d < (best?.1 ?? .infinity) { best = (region, d) }
        }
        return best.map { (region: $0.0, distanceKm: $0.1) }
    }
}

/// Resolves photo coordinates to regions entirely offline. Packs are tried in order, so pass the most
/// detailed packs first (Türkiye before the world). Not thread-safe (it caches); keep one per actor/task.
public final class RegionResolver {
    private let indexes: [RegionIndex]
    private let coastToleranceKm: Double
    private let cacheResolution: Double
    private var cache: [Int64: RegionRef?] = [:]

    public init(packs: [MapPack], coastToleranceKm: Double = 12, cacheResolution: Double = 0.01) {
        self.indexes = packs.map { RegionIndex(pack: $0, cellSize: $0.parentRegionID == nil ? 5 : 1) }
        self.coastToleranceKm = coastToleranceKm
        self.cacheResolution = cacheResolution
    }

    public func resolve(_ p: GeoPoint) -> RegionRef? {
        let qx = Int64((p.lon / cacheResolution).rounded()), qy = Int64((p.lat / cacheResolution).rounded())
        let key = qx &* 1_000_003 &+ qy
        if let cached = cache[key] { return cached }
        let result = uncachedResolve(p)
        cache[key] = result
        return result
    }

    private func uncachedResolve(_ p: GeoPoint) -> RegionRef? {
        for index in indexes {
            if let region = index.region(containing: p) {
                // A country hit that has a more detailed pack (e.g. world → Türkiye): refine to a province.
                if let sub = indexes.first(where: { $0.pack.parentRegionID == region.id && $0.pack.id != index.pack.id }),
                   let hit = sub.nearestRegion(to: p, maxDistanceKm: 50) {
                    return RegionRef(packID: sub.pack.id, regionID: hit.region.id)
                }
                return RegionRef(packID: index.pack.id, regionID: region.id)
            }
        }
        for index in indexes {
            if let hit = index.nearestRegion(to: p, maxDistanceKm: coastToleranceKm) {
                return RegionRef(packID: index.pack.id, regionID: hit.region.id)
            }
        }
        return nil
    }
}
