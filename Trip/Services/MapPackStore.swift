import Foundation
import Observation
import SwiftUI
import TripCore

/// Loads the bundled map packs once and caches their projected, drawable geometry.
@Observable
final class MapPackStore {
    /// Order matters for reverse geocoding: detailed packs first, the world last.
    static let bundledPackIDs = ["turkey", "world"]

    let packs: [MapPack]
    @ObservationIgnored private var renderables: [String: RenderableMap] = [:]

    init(bundle: Bundle = .main) {
        packs = Self.bundledPackIDs.compactMap { id in
            guard let url = bundle.url(forResource: id, withExtension: "json"),
                  let data = try? Data(contentsOf: url) else {
                assertionFailure("Missing map pack \(id).json")
                return nil
            }
            do {
                return try MapPack.decode(from: data)
            } catch {
                assertionFailure("Invalid map pack \(id): \(error)")
                return nil
            }
        }
    }

    func pack(_ id: String) -> MapPack? { packs.first { $0.id == id } }

    func region(_ ref: RegionRef) -> MapRegion? { pack(ref.packID)?.region(ref.regionID) }

    func name(of ref: RegionRef?) -> String {
        guard let ref else { return "Bilinmeyen yer" }
        return region(ref)?.name ?? ref.regionID
    }

    /// "İzmir, Türkiye" / "Fransa"
    func fullName(of ref: RegionRef?) -> String {
        guard let ref, let pack = pack(ref.packID) else { return name(of: ref) }
        if let parentID = pack.parentRegionID, let world = packs.first(where: { $0.parentRegionID == nil }),
           let parent = world.region(parentID) {
            return "\(name(of: ref)), \(parent.name)"
        }
        return name(of: ref)
    }

    /// The more detailed pack that subdivides a region (world `TUR` → `turkey`).
    func subpack(for ref: RegionRef) -> MapPack? {
        packs.first { $0.parentRegionID == ref.regionID && $0.id != ref.packID }
    }

    func renderable(_ packID: String) -> RenderableMap {
        if let cached = renderables[packID] { return cached }
        let pack = pack(packID) ?? packs[0]
        let map = RenderableMap(pack: pack)
        renderables[packID] = map
        return map
    }

    func makeResolver() -> RegionResolver { RegionResolver(packs: packs) }
}

/// A projected map plus one SwiftUI `Path` per region in unit space (built once, transformed while drawing).
struct RenderableMap {
    let pack: MapPack
    let projected: ProjectedMap
    let paths: [Path]
    let indexByID: [String: Int]

    init(pack: MapPack) {
        self.pack = pack
        projected = ProjectedMap(pack: pack)
        paths = projected.regions.map { region in
            var path = Path()
            for ring in region.rings where ring.count >= 3 {
                path.move(to: CGPoint(x: ring[0].x, y: ring[0].y))
                for p in ring.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
                path.closeSubpath()
            }
            return path
        }
        var index: [String: Int] = [:]
        for (i, r) in projected.regions.enumerated() { index[r.id] = i }
        indexByID = index
    }
}
