import SwiftUI
import TripCore

/// Draws a map pack with `Canvas`. Geometry lives in unit space; pinch/pan only changes the transform,
/// so borders stay crisp at every zoom level and nothing is re-tessellated while gesturing.
struct MapCanvasView: View {
    let map: RenderableMap
    /// Fill per region ID; regions not in the dictionary use `Theme.land`.
    let fills: [String: Color]
    var selectedID: String?
    /// Region to "pop" when it gets painted.
    var paintEvent: PaintEvent?
    var onPaintConsumed: () -> Void = {}
    var onTap: (String) -> Void

    private let maxZoom: CGFloat = 12

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var pinchStart: (zoom: CGFloat, offset: CGSize)?
    @State private var dragStart: CGSize?
    @State private var painting: (index: Int, start: Date)?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.animation(paused: painting == nil)) { timeline in
                Canvas { ctx, canvasSize in
                    draw(in: &ctx, size: canvasSize, now: timeline.date)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in handleTap(at: value.location, size: size) })
            .simultaneousGesture(magnifyGesture(size: size))
            .simultaneousGesture(dragGesture(size: size))
            .overlay(alignment: .topTrailing) {
                if zoom > 1.05 {
                    Button {
                        withAnimation(.spring(duration: 0.5)) { zoom = 1; offset = .zero }
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.subheadline.weight(.semibold))
                            .padding(10)
                            .background(.regularMaterial, in: Circle())
                    }
                    .padding(12)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Yakınlaştırmayı sıfırla")
                }
            }
            .onChange(of: paintEvent) { _, event in startPainting(event) }
            .onAppear { startPainting(paintEvent) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(map.pack.name) haritası")
        .accessibilityIdentifier("map.canvas")
    }

    // MARK: Transform

    /// Unit space → view space for the current zoom/pan.
    private func transform(for size: CGSize) -> CGAffineTransform {
        let aspect = CGFloat(map.projected.aspectRatio)
        let base = min(size.width / aspect, size.height) * 0.94
        let origin = CGPoint(x: (size.width - aspect * base) / 2, y: (size.height - base) / 2)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // view = center + offset + (origin + u * base - center) * zoom
        return CGAffineTransform.identity
            .translatedBy(x: center.x + offset.width, y: center.y + offset.height)
            .scaledBy(x: zoom, y: zoom)
            .translatedBy(x: origin.x - center.x, y: origin.y - center.y)
            .scaledBy(x: base, y: base)
    }

    private func clampedOffset(_ proposed: CGSize, size: CGSize, zoom: CGFloat) -> CGSize {
        let aspect = CGFloat(map.projected.aspectRatio)
        let base = min(size.width / aspect, size.height) * 0.94
        let maxX = max(0, (aspect * base * zoom - size.width) / 2) + size.width * 0.2
        let maxY = max(0, (base * zoom - size.height) / 2) + size.height * 0.2
        return CGSize(width: min(maxX, max(-maxX, proposed.width)), height: min(maxY, max(-maxY, proposed.height)))
    }

    // MARK: Drawing

    private func draw(in ctx: inout GraphicsContext, size: CGSize, now: Date) {
        let t = transform(for: size)
        let scale = t.a // uniform
        var mapCtx = ctx
        mapCtx.concatenate(t)

        let regions = map.projected.regions
        let paintProgress = painting.map { min(1, now.timeIntervalSince($0.start) / 0.9) }

        for (i, region) in regions.enumerated() {
            let fill = fills[region.id] ?? Theme.land
            if let painting, painting.index == i, let p = paintProgress {
                // Pop: grow slightly and settle back while the color fades in.
                let k = 1 + 0.18 * sin(p * .pi)
                let c = CGPoint(x: region.bounds.minX + region.bounds.width / 2, y: region.bounds.minY + region.bounds.height / 2)
                let pop = CGAffineTransform(translationX: c.x, y: c.y).scaledBy(x: k, y: k).translatedBy(x: -c.x, y: -c.y)
                mapCtx.fill(map.paths[i], with: .color(Theme.land), style: FillStyle(eoFill: true))
                var popCtx = mapCtx
                popCtx.opacity = 0.35 + 0.65 * p
                popCtx.fill(map.paths[i].applying(pop), with: .color(fill), style: FillStyle(eoFill: true))
            } else {
                mapCtx.fill(map.paths[i], with: .color(fill), style: FillStyle(eoFill: true))
            }
        }

        let hairline = 0.9 / scale
        for path in map.paths {
            mapCtx.stroke(path, with: .color(Theme.border), lineWidth: hairline)
        }

        if let painting, let p = paintProgress, p < 1 {
            var glow = mapCtx
            glow.opacity = 1 - p
            glow.stroke(map.paths[painting.index], with: .color(Theme.accent), lineWidth: (2 + 10 * p) / scale)
        }

        if let selectedID, let i = map.indexByID[selectedID] {
            mapCtx.stroke(map.paths[i], with: .color(.primary.opacity(0.85)),
                          style: StrokeStyle(lineWidth: 2.2 / scale, lineJoin: .round))
        }

        drawLabels(in: &ctx, transform: t, scale: scale)
    }

    private func drawLabels(in ctx: inout GraphicsContext, transform t: CGAffineTransform, scale: CGFloat) {
        let isWorld = map.pack.parentRegionID == nil
        let minSize: CGFloat = isWorld ? 90 : 52
        for region in map.projected.regions where CGFloat(region.size) * scale >= minSize {
            guard let name = map.pack.region(region.id)?.name else { continue }
            let screenWidth = CGFloat(region.mainBounds.width) * scale
            let fontSize = min(isWorld ? 11 : 13, 8 + CGFloat(region.size) * scale / 40)
            let resolved = ctx.resolve(
                Text(name)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.62)))
            // Only label regions wide enough to hold their name.
            guard resolved.measure(in: CGSize(width: 1000, height: 100)).width <= screenWidth * 0.8 else { continue }
            ctx.draw(resolved, at: CGPoint(x: region.label.x, y: region.label.y).applying(t))
        }
    }

    // MARK: Interaction

    private func handleTap(at location: CGPoint, size: CGSize) {
        let t = transform(for: size)
        let u = location.applying(t.inverted())
        let tolerance = 10 / t.a // ~10pt
        if let id = map.projected.hitTest(x: u.x, y: u.y, tolerance: tolerance) {
            UISelectionFeedbackGenerator().selectionChanged()
            onTap(id)
        }
    }

    private func magnifyGesture(size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? (zoom, offset)
                if pinchStart == nil { pinchStart = start }
                let newZoom = min(maxZoom, max(1, start.zoom * value.magnification))
                // Keep the point under the fingers fixed.
                let k = newZoom / start.zoom
                let anchor = CGSize(width: value.startLocation.x - size.width / 2, height: value.startLocation.y - size.height / 2)
                let proposed = CGSize(width: anchor.width - (anchor.width - start.offset.width) * k,
                                      height: anchor.height - (anchor.height - start.offset.height) * k)
                zoom = newZoom
                offset = clampedOffset(proposed, size: size, zoom: newZoom)
            }
            .onEnded { _ in pinchStart = nil }
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard pinchStart == nil else { return }
                let start = dragStart ?? offset
                if dragStart == nil { dragStart = start }
                offset = clampedOffset(CGSize(width: start.width + value.translation.width,
                                              height: start.height + value.translation.height),
                                       size: size, zoom: zoom)
            }
            .onEnded { _ in
                dragStart = nil
                if zoom <= 1.01 { withAnimation(.spring(duration: 0.4)) { offset = .zero } }
            }
    }

    private func startPainting(_ event: PaintEvent?) {
        guard let event, event.ref.packID == map.pack.id, let index = map.indexByID[event.ref.regionID] else { return }
        onPaintConsumed()
        painting = (index, .now)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        Task {
            try? await Task.sleep(for: .seconds(1))
            painting = nil
        }
    }
}
