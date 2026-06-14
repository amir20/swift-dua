import DiskKit
import SwiftUI

/// The Finder-style right-click menu shared by the rail rows, the rail's
/// type-location rows, and the donut slices — so every place that shows a folder
/// offers the same actions in the same order (primary first, destructive last).
///
/// `node` is the real directory behind the row. It's `nil` for a row that maps
/// to no single folder — the "Files in this folder" pseudo-segment and the type
/// aggregates — which can only reveal the current scope, not act on one folder.
@MainActor @ViewBuilder
func segmentMenuItems(for node: DirNode?, in model: ScanModel) -> some View {
    if let node {
        Button {
            model.jump(to: node)
        } label: {
            Label("Scan This Folder", systemImage: "magnifyingglass")
        }
        Button {
            model.revealInFinder(node)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        Divider()
        // An item already inside the Trash can't be re-trashed, so reclaiming it
        // is a permanent delete — the label has to say so rather than promise a
        // recoverable move. Both are destructive (rendered red).
        //
        // Disabled mid-scan: the in-place prune identifies the target by node
        // identity, which a still-streaming rebuild (`applyChild`) can restitch
        // away — the file would still be trashed, but the miss forces a full
        // rescan that supersedes the scan the user is watching. Greying the item
        // out is clearer than a silent no-op.
        if node.category == .trash {
            Button(role: .destructive) {
                model.trash(node)
            } label: {
                Label("Delete Permanently", systemImage: "trash.slash")
            }
            .disabled(model.scanning)
        } else {
            Button(role: .destructive) {
                model.trash(node)
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .disabled(model.scanning)
        }
    } else {
        Button {
            model.openInFinder()
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
    }
}
