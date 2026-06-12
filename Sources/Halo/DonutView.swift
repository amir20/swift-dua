import DiskKit
import SwiftUI

struct DonutView: View {
    @Bindable var model: ScanModel
    @State private var swept = false

    // Geometry from the design (460-pt coordinate space, center 230,230).
    private let side: CGFloat = 460
    private let r0: CGFloat = 122  // inner
    private let r1: CGFloat = 196  // outer
    private let rc0: CGFloat = 200  // amber inner
    private let rc1: CGFloat = 207  // amber outer
    private let ringRadius: CGFloat = 115  // progress ring radius (hugs the hole edge)
    private let ringWidth: CGFloat = 5
    private let ringArc: CGFloat = 0.02  // minimum fill, so early progress shows a nub

    var body: some View {
        ZStack {
            // background ring track
            Circle()
                .stroke(Palette.line2, lineWidth: r1 - r0)
                .frame(width: r0 + r1, height: r0 + r1)

            ForEach(model.arcs) { arc in
                slice(arc)
            }

            hole
            progressRing
        }
        .frame(width: side, height: side)
        // Resolve hover by geometry. Per-slice `.onHover` registers a tracking
        // area over each slice's *full* 460×460 frame (not its wedge), so the
        // topmost slice — the smallest, drawn last — would swallow every hover.
        // Mapping the cursor's angle to the arc under it picks the right slice.
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let p):
                let id = arcID(at: p)
                if model.hover != id { model.hover = id }
            case .ended:
                model.hover = nil
            }
        }
        .onTapGesture {
            // On macOS the cursor sits over the slice when clicked, so the live
            // hover identifies the tapped slice.
            if let h = model.hover, let seg = model.segments.first(where: { $0.id == h }) {
                model.tapSegment(seg)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.hover)
        .animation(.easeOut(duration: 0.18), value: model.expanded)
        .onChange(of: model.sweepKey) { _, _ in restartSweep() }
        .onAppear { restartSweep() }
    }

    private func restartSweep() {
        swept = false
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.8)) { swept = true }
        }
    }

    /// The id of the arc beneath a point in the donut's local (460×460) space.
    private func arcID(at p: CGPoint) -> String? {
        hitTestArc(at: p, in: model.arcs, center: side / 2, r0: r0, r1: r1)
    }

    @ViewBuilder
    private func slice(_ arc: Arc) -> some View {
        let a0 = arc.a0 + arc.gap / 2
        let a1Full = max(a0 + 0.002, arc.a1 - arc.gap / 2)
        let isHover =
            model.hover == arc.seg.id
            || (model.mode == .type && model.expanded == arc.seg.category)
        let dimmed = (model.hover != nil || model.expanded != nil) && !isHover
        let outer = isHover ? r1 + 9 : r1
        let end = swept ? a1Full : a0
        let recFrac =
            arc.seg.size > 0
            ? min(max(Double(arc.seg.recl) / Double(arc.seg.size), 0), 1) : 0

        ZStack {
            ArcShape(innerRadius: r0, outerRadius: outer, startAngle: a0, endAngle: end)
                .fill(arc.seg.color)
            ArcShape(innerRadius: r0, outerRadius: outer, startAngle: a0, endAngle: end)
                .stroke(Palette.bg, lineWidth: 2)
            if recFrac > 0.001 {
                ArcShape(
                    innerRadius: rc0, outerRadius: rc1,
                    startAngle: a0,
                    endAngle: swept ? a0 + (a1Full - a0) * recFrac : a0
                )
                .fill(Palette.reclaim)
            }
        }
        .opacity(dimmed ? 0.32 : 1)
        .allowsHitTesting(false)  // hover & tap are resolved by angle at the donut level
        // Hit-testing is geometric, which leaves VoiceOver nothing to land on —
        // expose each slice as its own actionable element.
        .accessibilityElement()
        .accessibilityLabel(
            Text(
                "\(arc.seg.label), \(formatSize(arc.seg.size)), \(percent(arc.seg.size, of: model.total).clean) percent"
            )
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tapSegment(arc.seg) }
    }

    /// Determinate "scanning" indicator: a blue arc hugging the inside of the
    /// donut that fills clockwise from 12 o'clock as the walk progresses. The
    /// exact byte total isn't known until the scan ends, so the fill tracks
    /// `scanFraction` — the share of *discovered* directories already listed,
    /// clamped so it only ever advances. `showRing` gates it behind a short
    /// delay so quick scans never flash it; the live byte/file counter in the
    /// hole carries the concrete "how much so far" signal.
    @ViewBuilder
    private var progressRing: some View {
        if model.showRing {
            Circle()
                .trim(from: 0, to: max(ringArc, CGFloat(model.scanFraction)))
                .stroke(
                    Palette.progress,
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .frame(width: ringRadius * 2, height: ringRadius * 2)
                .rotationEffect(.degrees(-90))  // start the fill at 12 o'clock
                .animation(.easeOut(duration: 0.3), value: model.scanFraction)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    private var hole: some View {
        let f = model.focus
        let scope = model.displayName(model.current?.name ?? "~")
        let scanning = model.scanning && f == nil
        let name = f?.label ?? scope
        let size = scanning ? model.liveBytes : (f?.size ?? model.total)
        let recl = scanning ? 0 : (f?.recl ?? model.reclTotal)
        let subtitle: String = {
            if let err = model.scanError { return err }
            if scanning { return "scanning… \(model.liveFiles.formatted()) files" }
            if let f { return "\(percent(f.size, of: model.total).clean)% of \(scope)" }
            if model.mode == .type { return "by type · in \(scope)" }
            return model.path.count == 1 ? "used on \(model.volumeLabel)" : "in this folder"
        }()

        return ZStack {
            // Solid light center: the hole carries dark text, so it needs a
            // light, opaque backing (glass here rendered as a dark blob and
            // killed contrast). The glass treatment lives on the floating
            // controls instead.
            Circle().fill(Palette.bg).frame(width: (r0 - 6) * 2, height: (r0 - 6) * 2)
            VStack(spacing: 3) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(f != nil ? Palette.ink2 : Palette.ink3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(formatSize(size))
                    .font(.system(size: 38, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink4)
                if recl > 0 {
                    HStack(spacing: 6) {
                        Circle().fill(Palette.reclaim).frame(width: 8, height: 8)
                        Text("\(formatSize(recl)) reclaimable")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Palette.reclaim)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(width: (r0 - 10) * 2)
        }
    }
}

extension Double {
    /// Drops a trailing `.0` so "12.0%" prints as "12%".
    var clean: String {
        self == rounded() ? String(Int(self)) : String(self)
    }
}

/// The id of the arc beneath `p` in a donut centered at `(center, center)` with
/// ring radii `r0`/`r1`, or `nil` outside the ring band. Angles follow `Arc`:
/// 12 o'clock = -π/2, increasing clockwise. Kept pure so the hover hit-test is
/// unit-testable without a live view.
func hitTestArc(at p: CGPoint, in arcs: [Arc], center: CGFloat, r0: CGFloat, r1: CGFloat) -> String?
{
    let dx = p.x - center
    let dy = p.y - center
    let r = sqrt(dx * dx + dy * dy)
    guard r >= r0, r <= r1 + 9 else { return nil }
    var theta = atan2(dy, dx)
    if theta < -Double.pi / 2 { theta += 2 * .pi }  // wrap into [-π/2, 3π/2)
    return arcs.first { theta >= $0.a0 && theta < $0.a1 }?.seg.id
}
