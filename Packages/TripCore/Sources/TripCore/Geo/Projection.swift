import Foundation

public enum ProjectionKind: String, Codable, Sendable {
    /// Conformal; good for a single country such as Türkiye.
    case mercator
    /// Equal-area world projection (Šavrič, Patterson & Jenny 2018); pleasant for world maps.
    case equalEarth
}

public protocol MapProjection: Sendable {
    func project(_ p: GeoPoint) -> PlanarPoint
    func unproject(_ p: PlanarPoint) -> GeoPoint
}

public extension ProjectionKind {
    var projection: any MapProjection {
        switch self {
        case .mercator: MercatorProjection()
        case .equalEarth: EqualEarthProjection()
        }
    }
}

public struct MercatorProjection: MapProjection {
    public init() {}

    public func project(_ p: GeoPoint) -> PlanarPoint {
        let lat = max(-85.0, min(85.0, p.lat)) * .pi / 180
        return PlanarPoint(x: p.lon * .pi / 180, y: log(tan(.pi / 4 + lat / 2)))
    }

    public func unproject(_ p: PlanarPoint) -> GeoPoint {
        GeoPoint(lon: p.x * 180 / .pi, lat: (2 * atan(exp(p.y)) - .pi / 2) * 180 / .pi)
    }
}

public struct EqualEarthProjection: MapProjection {
    private static let a1 = 1.340264, a2 = -0.081106, a3 = 0.000893, a4 = 0.003796
    private static let m = 3.0.squareRoot() / 2

    public init() {}

    public func project(_ p: GeoPoint) -> PlanarPoint {
        let (a1, a2, a3, a4, m) = (Self.a1, Self.a2, Self.a3, Self.a4, Self.m)
        let lambda = p.lon * .pi / 180
        let phi = p.lat * .pi / 180
        let theta = asin(m * sin(phi))
        let t2 = theta * theta, t6 = t2 * t2 * t2
        let x = lambda * cos(theta) / (m * (a1 + 3 * a2 * t2 + t6 * (7 * a3 + 9 * a4 * t2)))
        let y = theta * (a1 + a2 * t2 + t6 * (a3 + a4 * t2))
        return PlanarPoint(x: x, y: y)
    }

    public func unproject(_ p: PlanarPoint) -> GeoPoint {
        let (a1, a2, a3, a4, m) = (Self.a1, Self.a2, Self.a3, Self.a4, Self.m)
        var theta = p.y
        for _ in 0..<12 { // Newton–Raphson
            let t2 = theta * theta, t6 = t2 * t2 * t2
            let fy = theta * (a1 + a2 * t2 + t6 * (a3 + a4 * t2)) - p.y
            let fpy = a1 + 3 * a2 * t2 + t6 * (7 * a3 + 9 * a4 * t2)
            let delta = fy / fpy
            theta -= delta
            if abs(delta) < 1e-12 { break }
        }
        let t2 = theta * theta, t6 = t2 * t2 * t2
        let lambda = m * p.x * (a1 + 3 * a2 * t2 + t6 * (7 * a3 + 9 * a4 * t2)) / cos(theta)
        let phi = asin(sin(theta) / m)
        return GeoPoint(lon: lambda * 180 / .pi, lat: phi * 180 / .pi)
    }
}
