import DiskKit
import SwiftUI

/// Confirmation dialog for moving reclaimable directories to the Trash. Lists
/// every safe target with a checkbox (high-confidence pre-checked), a live
/// "selected" tally, and the destructive action. Owns only its selection.
struct ReclaimSheet: View {
    let plan: [ReclaimItem]
    let onConfirm: ([ReclaimItem]) -> Void
    let onCancel: () -> Void

    @State private var selected: Set<ReclaimItem.ID>

    init(
        plan: [ReclaimItem],
        onConfirm: @escaping ([ReclaimItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.plan = plan
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _selected = State(initialValue: Set(plan.filter(\.preselected).map(\.id)))
    }

    private var chosen: [ReclaimItem] { plan.filter { selected.contains($0.id) } }
    private var total: Int64 { chosen.reduce(0) { $0 + $1.size } }
    /// True when any chosen target is already in the Trash, so confirming will
    /// permanently delete it rather than move it to the Trash.
    private var hasPermanentDelete: Bool { chosen.contains(where: \.permanentDelete) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.line)
            list
            Divider().overlay(Palette.line)
            footer
        }
        .frame(width: 480)
        .background(Palette.bg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Move to Trash?")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text(
                hasPermanentDelete
                    ? "Review what Halo will remove. Items already in the Trash are deleted permanently."
                    : "Review what Halo will move to the Trash. Everything is recoverable."
            )
            .font(.system(size: 12))
            .foregroundStyle(Palette.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(plan) { item in row(item) }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
        .frame(maxHeight: 320)
    }

    private func row(_ item: ReclaimItem) -> some View {
        let on = selected.contains(item.id)
        return HStack(spacing: 11) {
            Image(systemName: on ? "checkmark.square.fill" : "square")
                .font(.system(size: 16))
                .foregroundStyle(on ? Palette.reclaim : Palette.ink4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1).truncationMode(.middle)
                    confidencePill(item.confidence)
                }
                Text(
                    "\(abbreviated(item.url.deletingLastPathComponent().path))  ·  \(item.signalLabel)"
                )
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.ink4)
                .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(formatSize(item.size))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(on ? Palette.bg3 : .clear))
        .contentShape(Rectangle())
        .onTapGesture { toggle(item.id) }
        .help(item.reason)
    }

    private func confidencePill(_ c: ReclaimConfidence) -> some View {
        let high = c == .high
        return Text(high ? "high" : "medium")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(high ? Palette.reclaim : Palette.ink3)
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(Capsule().fill((high ? Palette.reclaim : Palette.ink4).opacity(0.14)))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(
                "\(chosen.count) of \(plan.count) safe target\(plan.count == 1 ? "" : "s") selected · \(formatSize(total))"
            )
            .font(.system(size: 12))
            .foregroundStyle(Palette.ink3)
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(.glass)
            Button {
                onConfirm(chosen)
            } label: {
                Label(
                    hasPermanentDelete ? "Remove" : "Move to Trash",
                    systemImage: "trash"
                )
                .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.reclaim)
            .disabled(chosen.isEmpty)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func toggle(_ id: ReclaimItem.ID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        // Require a path-component boundary so "/Users/alice" doesn't match
        // "/Users/alicetmp/…" and mangle it to "~tmp/…".
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
