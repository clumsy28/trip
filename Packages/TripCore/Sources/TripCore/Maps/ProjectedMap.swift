import Foundation

/// A map pack projected into a "unit space" ready for drawing:
/// y grows downwards, the map's height is exactly 1 and its width is `aspectRatio`.
/// The UI only has to scale/translate this space into the view.
public struct ProjectedMap: Sendable {
    public struct Region: Sendable, Identifiable {
        public let id: String
        public let rings: [[PlanarPoint]]
        public let bounds: BoundingBox
        /// Bounds of the largest part only (mainland without far-away islands), for label fitting.
        public let mainBounds: BoundingBox
        public let label: PlanarPoint
        /// Approximate size of the main part in unit space, used to decide when labels fit.
        public var size: Double { max(mainBounds.width, mainBounds.height) }
    }

    public let packID: String
    public let aspectRatio: Double
    public let regions: [Region]
    private let projectionKind: ProjectionKind
    private let origin: PlanarPoint // (minX, maxY) of the projected bounds
    private let scale: Double       // 1 / projected height

    public init(pack: MapPack) {
        let projection = pack.projection.projection
        var raw: [(id: String, rings: [[PlanarPoint]], label: PlanarPoint)] = []
        var total = BoundingBox.empty
        for region in pack.regions {
            let rings = region.rings.map { ring in ring.map { projection.project($0) } }
            for ring in rings { for p in ring { total.include(x: p.x, y: p.y) } }
            raw.append((region.id, rings, projection.project(region.label)))
        }
        let height = max(total.height, .ulpOfOne)
        func unit(_ p: PlanarPoint) -> PlanarPoint {
            PlanarPoint(x: (p.x - total.minX) / height, y: (total.maxY - p.y) / height)
        }
        self.packID = pack.id
        self.aspectRatio = total.width / height
        self.projectionKind = pack.projection
        self.origin = PlanarPoint(x: total.minX, y: total.maxY)
        self.scale = 1 / height
        self.regions = raw.map { r in
            var b = BoundingBox.empty
            var main = BoundingBox.empty
            let rings = r.rings.map { ring in
                var rb = BoundingBox.empty
                let projected = ring.map { p -> PlanarPoint in
                    let u = unit(p)
                    rb.include(x: u.x, y: u.y)
                    return u
                }
                b = b.union(rb)
                if rb.width * rb.height > (main.isEmpty ? -1 : main.width * main.height) { main = rb }
                return projected
            }
            return Region(id: r.id, rings: rings, bounds: b, mainBounds: main.isEmpty ? b : main, label: unit(r.label))
        }
    }

    /// Projects a geographic coordinate into this map's unit space.
    public func unitPoint(for p: GeoPoint) -> PlanarPoint {
        let q = projectionKind.projection.project(p)
        return PlanarPoint(x: (q.x - origin.x) * scale, y: (origin.y - q.y) * scale)
    }

    /// The region under a point in unit space, if any.
    public func hitTest(x: Double, y: Double) -> String? {
        // Iterate backwards so regions drawn last (on top) win.
        for region in regions.reversed() where region.bounds.contains(x: x, y: y) {
            if PolygonMath.contains(x: x, y: y, rings: region.rings) { return region.id }
        }
        return nil
    }

    /// Like `hitTest`, but if the point is on water/border it picks the nearest region within `tolerance`
    /// (unit space). Makes tapping tiny regions and coastlines forgiving.
    public func hitTest(x: Double, y: Double, tolerance: Double) -> String? {
        if let id = hitTest(x: x, y: y) { return id }
        var best: (id: String, d2: Double)?
        let t2 = tolerance * tolerance
        for region in regions where region.bounds.expanded(by: tolerance).contains(x: x, y: y) {
            for ring in region.rings where ring.count >= 2 {
                var prev = ring[ring.count - 1]
                for cur in ring {
                    let d2 = PolygonMath.distanceSquared(px: x, py: y, ax: prev.x, ay: prev.y, bx: cur.x, by: cur.y)
                    if d2 <= t2, d2 < (best?.d2 ?? .infinity) { best = (region.id, d2) }
                    prev = cur
                }
            }
        }
        return best?.id
    }
}
