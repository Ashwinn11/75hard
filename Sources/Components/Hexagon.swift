import SwiftUI
import UIKit

// Pointy-top hex aspect: height = width × (2/√3).
let kHexAspect: CGFloat = 1.1547005

// MARK: - RoundedHexagon
// The single shared hexagon silhouette. Pointy-top by default (point at top/bottom).
// Regular hexagon centered in its rect, with rounded corners.
struct RoundedHexagon: Shape {
    var cornerRadius: CGFloat = 6
    var flatTop: Bool = false

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        let r: CGFloat = flatTop
            ? min(rect.width / 2, rect.height / 1.7320508)
            : min(rect.width / 1.7320508, rect.height / 2)
        let base: CGFloat = flatTop ? 0 : -(.pi / 2)

        var verts: [CGPoint] = []
        for i in 0..<6 {
            let a = base + CGFloat(i) * (.pi / 3)
            verts.append(CGPoint(x: cx + r * cos(a), y: cy + r * sin(a)))
        }

        let cr = min(cornerRadius, r * 0.5)
        var path = Path()
        for i in 0..<6 {
            let v = verts[i]
            let p = verts[(i + 5) % 6]
            let n = verts[(i + 1) % 6]
            let toP = unit(v, p), toN = unit(v, n)
            let a = CGPoint(x: v.x + toP.x * cr, y: v.y + toP.y * cr)
            let b = CGPoint(x: v.x + toN.x * cr, y: v.y + toN.y * cr)
            if i == 0 { path.move(to: a) } else { path.addLine(to: a) }
            path.addQuadCurve(to: b, control: v)
        }
        path.closeSubpath()
        return path
    }

    private func unit(_ f: CGPoint, _ t: CGPoint) -> CGPoint {
        let dx = t.x - f.x, dy = t.y - f.y
        let len = max(0.0001, (dx * dx + dy * dy).squareRoot())
        return CGPoint(x: dx / len, y: dy / len)
    }
}

// MARK: - HiveHex (solid, gradient)
// Used for: stats cards, per-habit chips, widget preview, swatches.
struct HiveHex<Content: View>: View {
    var colors: [Color]
    var width: CGFloat
    var cornerRadius: CGFloat? = nil
    var selected: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        let cr = cornerRadius ?? max(3, width * 0.12)
        ZStack {
            RoundedHexagon(cornerRadius: cr)
                .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            content()
        }
        .frame(width: width, height: width * kHexAspect)
        .overlay {
            if selected {
                RoundedHexagon(cornerRadius: cr)
                    .stroke(Theme.ink.opacity(0.85), lineWidth: 2.5)
                    .frame(width: width, height: width * kHexAspect)
            }
        }
    }
}

extension HiveHex where Content == EmptyView {
    init(color: HabitColor, width: CGFloat, selected: Bool = false) {
        self.init(colors: color.stops, width: width, selected: selected) { EmptyView() }
    }
}

// MARK: - HiveComb (ringed photo cells)
// The signature shareable visual. The silhouette is subdivided into a pointy-top honeycomb
// that grows ring by ring: ring 1 = 7 cells, ring 2 = 19, ring 3 = 37 … = 1 + 3R(R+1).
// Each cell = one proof-photo log.
enum CombCell {
    case empty
    case photo(Data)
    case logged          // logged without a photo — colored gradient + check
    case sample          // soft demo cell — never pure black
    case camera          // tappable "log today" affordance
}

struct HiveComb: View {
    var color: HabitColor
    var cells: [CombCell]
    var width: CGFloat
    var minRings: Int = 1
    var forceRings: Int? = nil
    /// Cap how many cells are actually drawn. A challenge hive shows exactly N target cells
    /// (arc-filling the final, partial ring) instead of the whole enclosing ring. nil = full ring.
    var visibleCells: Int? = nil
    var onLog: (() -> Void)? = nil

    private static let sqrt3: CGFloat = 1.7320508

    private func rings(for count: Int) -> Int {
        var r = max(1, minRings)
        while (1 + 3 * r * (r + 1)) < count { r += 1 }
        return max(r, forceRings ?? 0)
    }

    // Ordered axial coords: center, then ring 1, ring 2 …
    private func layout(_ R: Int) -> [(q: Int, r: Int)] {
        var out: [(q: Int, r: Int)] = [(0, 0)]
        let dirs = [(1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1)]
        for k in 1...max(1, R) {
            var q = dirs[4].0 * k, r = dirs[4].1 * k
            for i in 0..<6 {
                for _ in 0..<k { out.append((q, r)); q += dirs[i].0; r += dirs[i].1 }
            }
        }
        return out
    }

    var body: some View {
        let R = rings(for: cells.count)
        let coords = layout(R)
        let blobW = width
        let blobH = width * kHexAspect
        // Cell circumradius so the cluster fills ~93% of the blob width.
        let cs = 0.93 * blobW / (Self.sqrt3 * CGFloat(2 * R + 1))
        let cr = cs * 0.92   // tight honeycomb nesting — hairline gap between cells

        ZStack {
            RoundedHexagon(cornerRadius: blobW * 0.12)
                .fill(LinearGradient(colors: [color.stops[0], color.stops[1]],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: blobW, height: blobH)

            ForEach(0..<min(visibleCells ?? coords.count, coords.count), id: \.self) { i in
                let c = coords[i]
                let dx = Self.sqrt3 * cs * (CGFloat(c.q) + CGFloat(c.r) / 2)
                let dy = 1.5 * cs * CGFloat(c.r)
                cellView(cells.indices.contains(i) ? cells[i] : .empty, cr: cr)
                    .position(x: blobW / 2 + dx, y: blobH / 2 + dy)
            }
        }
        .frame(width: blobW, height: blobH)
    }

    @ViewBuilder
    private func cellView(_ cell: CombCell, cr: CGFloat) -> some View {
        let corner = max(1.5, cr * 0.32)
        let cw = Self.sqrt3 * cr      // exact cell width  — every hex identical
        let ch = 2 * cr              // exact cell height
        switch cell {
        case .photo(let data):
            ZStack {
                RoundedHexagon(cornerRadius: corner).fill(Color.black.opacity(0.85))
                if let img = ImageProcessing.thumbnail(data, maxPixel: cw * 3) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: cw, height: ch)
                        .clipShape(RoundedHexagon(cornerRadius: corner))
                }
            }
            .frame(width: cw, height: ch)

        case .logged:
            ZStack {
                RoundedHexagon(cornerRadius: corner)
                    .fill(LinearGradient(colors: [color.stops[0], color.stops[1]],
                                         startPoint: .top, endPoint: .bottom))
                Image(systemName: "checkmark")
                    .font(.system(size: max(5, cr * 0.45), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .frame(width: cw, height: ch)

        case .sample:
            ZStack {
                RoundedHexagon(cornerRadius: corner)
                    .fill(LinearGradient(colors: [Theme.coral.opacity(0.5), Theme.ring],
                                         startPoint: .top, endPoint: .bottom))
                Image(systemName: "sparkles")
                    .font(.system(size: max(6, cr * 0.5)))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: cw, height: ch)

        case .camera:
            let cameraCell = ZStack {
                RoundedHexagon(cornerRadius: corner).fill(Color.white.opacity(0.34))
                Image(systemName: "camera")
                    .font(.system(size: max(7, cr * 0.5)))
                    .foregroundStyle(Theme.ink.opacity(0.55))
            }
            .frame(width: cw, height: ch)
            if let onLog {
                Button { onLog() } label: { cameraCell }.buttonStyle(.plain)
            } else {
                cameraCell.allowsHitTesting(false)
            }

        case .empty:
            RoundedHexagon(cornerRadius: corner)
                .fill(Color.white.opacity(0.30))
                .frame(width: cw, height: ch)
        }
    }
}

// MARK: - GrowingHive
// A TIGHT honeycomb of exactly N hexes — one per logged day (+ an optional "log today" cell).
// Day 1 = 1 hex, day 2 = 2 hexes, growing ring by ring. No blob, no empty padding; the cluster
// is sized to its contents and the hexes shrink so the whole thing stays within `maxWidth`.
struct GrowingHive: View {
    var color: HabitColor
    var cells: [CombCell]                 // logged hexes (+ optional .camera) — no empties
    var maxWidth: CGFloat = 240
    var maxHeight: CGFloat = 240
    var maxHexWidth: CGFloat = 150
    private static let s3: CGFloat = 1.7320508

    private static func rings(_ n: Int) -> Int {
        var r = 0
        while 1 + 3 * r * (r + 1) < n { r += 1 }
        return r
    }
    private static func layout(_ n: Int) -> [(q: Int, r: Int)] {
        var out: [(Int, Int)] = [(0, 0)]
        let R = rings(n)
        if R >= 1 {
            // CCW spiral starting at the East corner → horizontal-first growth:
            // n=2 is a side-by-side pair, n=4 is a 2×2 block, then it keeps packing.
            let steps = [(0, -1), (-1, 0), (-1, 1), (0, 1), (1, 0), (1, -1)]
            for k in 1...R {
                var q = k, r = 0
                for i in 0..<6 { for _ in 0..<k { out.append((q, r)); q += steps[i].0; r += steps[i].1 } }
            }
        }
        return Array(out.prefix(n))
    }

    var body: some View {
        let n = max(cells.count, 1)
        let coords = Self.layout(n)
        let centers = coords.map { CGPoint(x: Self.s3 * (CGFloat($0.q) + CGFloat($0.r) / 2), y: 1.5 * CGFloat($0.r)) }
        let minX = centers.map(\.x).min() ?? 0, maxX = centers.map(\.x).max() ?? 0
        let minY = centers.map(\.y).min() ?? 0, maxY = centers.map(\.y).max() ?? 0
        let unitW = (maxX - minX) + Self.s3                          // total width in circumradius units
        let unitH = (maxY - minY) + 2                                // total height in circumradius units
        let cs = min(maxHexWidth / Self.s3, maxWidth / unitW, maxHeight / unitH)   // circumradius in points
        let hexW = Self.s3 * cs, hexH = 2 * cs
        return ZStack {
            ForEach(0..<n, id: \.self) { i in
                cell(cells.indices.contains(i) ? cells[i] : .empty, w: hexW, h: hexH)
                    .position(x: (centers[i].x - minX) * cs + hexW / 2,
                              y: (centers[i].y - minY) * cs + hexH / 2)
            }
        }
        .frame(width: (maxX - minX) * cs + hexW, height: (maxY - minY) * cs + hexH)
    }

    @ViewBuilder private func cell(_ c: CombCell, w: CGFloat, h: CGFloat) -> some View {
        let corner = max(2, w * 0.14)
        switch c {
        case .photo(let data):
            ZStack {
                RoundedHexagon(cornerRadius: corner).fill(Color.black.opacity(0.85))
                if let img = ImageProcessing.thumbnail(data, maxPixel: w * 3) {
                    Image(uiImage: img).resizable().scaledToFill().frame(width: w, height: h)
                        .clipShape(RoundedHexagon(cornerRadius: corner))
                }
            }.frame(width: w, height: h)
        case .logged:
            ZStack {
                RoundedHexagon(cornerRadius: corner).fill(color.gradient)
                Image(systemName: "checkmark").font(.system(size: max(8, w * 0.3), weight: .semibold)).foregroundStyle(.white.opacity(0.95))
            }.frame(width: w, height: h)
        case .camera:
            ZStack {
                RoundedHexagon(cornerRadius: corner).fill(color.stops[0].opacity(0.5))
                Image(systemName: "plus").font(.system(size: max(10, w * 0.34), weight: .bold)).foregroundStyle(color.onColor)
            }.frame(width: w, height: h)
        default:
            RoundedHexagon(cornerRadius: corner).fill(color.stops[0].opacity(0.25)).frame(width: w, height: h)
        }
    }
}
