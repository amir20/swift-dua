import DiskKit
import SwiftUI

struct RailView: View {
    @Bindable var model: ScanModel

    var body: some View {
        VStack(spacing: 0) {
            header

            // Plain-language overview of the current scope. Only meaningful once a
            // scan has produced segments to describe; it generates itself.
            if !model.scanning && !model.segments.isEmpty {
                SummaryCard(model: model)
                    .animation(.easeInOut(duration: 0.3), value: model.summaryState)
            }

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(model.segments) { seg in
                        row(seg)
                        if model.mode == .type, model.expanded == seg.category {
                            locations(for: seg)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }

            footer
        }
        .frame(width: 320)
        .background(Palette.bg2)
        .overlay(alignment: .leading) { Divider().overlay(Palette.line) }
    }

    /// The rail's section label plus, when the scan couldn't read everything,
    /// a quiet coverage caveat — but only when the Full Disk Access banner isn't
    /// already making the same point up top. Banner owns the *ask*, this owns the
    /// *fact*, so the two never repeat each other.
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(headerText.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Palette.ink4)
            if model.skippedDirs > 0 && !model.showFDABanner {
                Text(
                    "\(model.skippedDirs) folder\(model.skippedDirs == 1 ? "" : "s") couldn't be read"
                )
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16).padding(.bottom, 8)
    }

    private var headerText: String {
        let scope = model.displayName(model.current?.name ?? "~")
        return model.mode == .type ? "Types in \(scope)" : "Breakdown of \(scope)"
    }

    private func row(_ seg: Segment) -> some View {
        let on = model.hover == seg.id || (model.mode == .type && model.expanded == seg.category)
        let isExp = model.mode == .type && model.expanded == seg.category
        return HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 3)
                .fill(seg.color)
                .frame(width: 11, height: 11)
            VStack(alignment: .leading, spacing: 1) {
                Text(seg.label)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(seg.isType ? "across this folder" : seg.category.label)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink4)
            }
            Spacer(minLength: 6)
            if seg.recl > 0 {
                Text("\(formatSize(seg.recl)) free")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.reclaim)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Palette.reclaim.opacity(0.12)))
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(formatSize(seg.size))
                    .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                Text("\(percent(seg.size, of: model.total).clean)%")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.ink4)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.ink4)
                .rotationEffect(.degrees(isExp ? 90 : 0))
                .opacity((seg.drillable || seg.isType) ? (on ? 1 : 0) : 0)
                .frame(width: 8)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9).fill(on ? Palette.bg : .clear))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(on ? Palette.line : .clear))
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { model.hover = seg.id } else if model.hover == seg.id { model.hover = nil }
        }
        .onTapGesture { model.tapSegment(seg) }
    }

    private func locations(for seg: Segment) -> some View {
        // Cached on the model (rebuilt only when the expanded type changes),
        // so hovering rail rows no longer re-walks the subtree each frame.
        let locs = Array(model.expandedLocations.prefix(6))
        return VStack(spacing: 7) {
            ForEach(locs.indices, id: \.self) { i in
                let loc = locs[i]
                HStack(spacing: 9) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(seg.color)
                        .frame(width: 6, height: 6)
                    Text(model.fullPath(loc.node))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    if loc.recl > 0 {
                        Text("\(formatSize(loc.recl)) free")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.reclaim)
                    }
                    Text(formatSize(loc.size))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .contentShape(Rectangle())
                .onTapGesture { model.jump(to: loc.node) }
            }
        }
        .padding(.leading, 24).padding(.trailing, 12).padding(.vertical, 4)
    }

    private var footer: some View {
        let enabled = !model.reclaimTargets.isEmpty
        return VStack(spacing: 7) {
            Button {
                model.showReclaimSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                    Text("Reclaim \(formatSize(model.reclTotal))")
                }
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 40)
                .glassEffect(.regular.tint(Palette.reclaim), in: .rect(cornerRadius: 10))
                // .plain buttons only hit-test opaque label content, and the glass
                // background doesn't count — without this, only the icon/text is clickable.
                .contentShape(.rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)

            // Only ever a transient result of the last reclaim — the "what's safe /
            // recoverable" reassurance lives in the reclaim sheet, where the user
            // actually makes the decision.
            if let note = reclaimResultNote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        (model.lastReclaim?.failed ?? 0) > 0 ? Palette.reclaim : Palette.ink4)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 12)
        .overlay(alignment: .top) { Divider().overlay(Palette.line) }
        .sheet(isPresented: $model.showReclaimSheet) {
            ReclaimSheet(
                plan: model.reclaimPlan,
                onConfirm: { model.performReclaim($0) },
                onCancel: { model.showReclaimSheet = false })
        }
    }

    private var reclaimResultNote: String? {
        guard let r = model.lastReclaim else { return nil }
        var note = "Moved \(r.trashed) to Trash"
        if r.failed > 0 { note += " · \(r.failed) couldn't be removed" }
        return note
    }
}
