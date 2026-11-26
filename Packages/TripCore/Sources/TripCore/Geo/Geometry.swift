import Foundation

/// A geographic coordinate in degrees.
public struct GeoPoint: Hashable, Sendable, Codable {
    public var lon: Double
    public var lat: Double

    public init(lon: Double, lat: Double) {
        self.lon = lon
        self.lat = lat
    }
}

/// A point on a projected (planar) map. `y` grows northwards.
public struct PlanarPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Axis-aligned rectangle used for both geographic (lon/lat) and planar bounds.
public struct BoundingBox: Hashable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public static let empty = BoundingBox(minX: .infinity, minY: .infinity, maxX: -.infinity, maxY: -.infinity)

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var isEmpty: Bool { minX > maxX || minY > maxY }

    public func contains(x: Double, y: Double) -> Bool {
        x >= minX && x <= maxX && y >= minY && y <= maxY
    }

    public func expanded(by d: Double) -> BoundingBox {
        BoundingBox(minX: minX - d, minY: minY - d, maxX: maxX + d, maxY: maxY + d)
    }

    public func union(_ o: BoundingBox) -> BoundingBox {
        BoundingBox(minX: min(minX, o.minX), minY: min(minY, o.minY), maxX: max(maxX, o.maxX), maxY: max(maxY, o.maxY))
    }

    public mutating func include(x: Double, y: Double) {
        minX = min(minX, x); minY = min(minY, y)
        maxX = max(maxX, x); maxY = max(maxY, y)
    }
}

/// Anything with planar-ish x/y components (lon/lat for `GeoPoint`).
public protocol Point2D {
    var px: Double { get }
    var py: Double { get }
}

extension GeoPoint: Point2D {
    @inlinable public var px: Double { lon }
    @inlinable public var py: Double { lat }
}

extension PlanarPoint: Point2D {
    @inlinable public var px: Double { x }
    @inlinable public var py: Double { y }
}

public enum PolygonMath {
    /// Even-odd ray casting over every ring of a (multi)polygon. Holes are handled by the even-odd rule,
    /// so the rings of all parts can be passed together.
    public static func contains<P: Point2D>(x: Double, y: Double, rings: [[P]]) -> Bool {
        var inside = false
        for ring in rings {
            let n = ring.count
            guard n >= 3 else { continue }
            var j = n - 1
            for i in 0..<n {
                let xi = ring[i].px, yi = ring[i].py
                let xj = ring[j].px, yj = ring[j].py
                if (yi > y) != (yj > y) {
                    let crossX = (xj - xi) * (y - yi) / (yj - yi) + xi
                    if x < crossX { inside.toggle() }
                }
                j = i
            }
        }
        return inside
    }

    /// Squared distance from point p to segment ab in a planar space.
    public static func distanceSquared(px: Double, py: Double, ax: Double, ay: Double, bx: Double, by: Double) -> Double {
        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        var t = len2 > 0 ? ((px - ax) * dx + (py - ay) * dy) / len2 : 0
        t = max(0, min(1, t))
        let cx = ax + t * dx - px, cy = ay + t * dy - py
        return cx * cx + cy * cy
    }
}
