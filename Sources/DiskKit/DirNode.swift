import Foundation

/// A directory in the scanned tree.
///
/// To keep a whole-home-folder scan tractable, the tree stores **directories
/// only**: individual files are not nodes — instead each directory aggregates
/// the bytes of the files directly inside it, bucketed by category
/// (`fileBytes`). `size` is the full subtree total (own files + descendants),
/// computed bottom-up at construction.
///
/// `@unchecked Sendable`: the tree is fully built on a background thread and
/// then handed to the main actor as an immutable value. The only post-`init`
/// mutation is wiring each child's `parent`, which happens inside `init` before
/// the node escapes.
public final class DirNode: Identifiable, @unchecked Sendable {
    public let name: String
    /// This directory's own classification (drives folder-mode slice color and
    /// the "where does this type live" grouping).
    public let category: FileCategory
    /// Why this whole directory is a reclaimable target (with confidence/reason),
    /// or `nil` to keep. See `ReclaimMark`.
    public let reclaim: ReclaimMark?
    /// Bytes of files directly in this directory, keyed by the file's category.
    public let fileBytes: [FileCategory: Int64]
    public let children: [DirNode]
    /// Total subtree size in bytes (own files + all descendants).
    public let size: Int64

    /// Whether the directory is a reclaimable target. Keeps the many read sites
    /// (`Derive`, the rail badges) working against the richer `reclaim`.
    public var isReclaimable: Bool { reclaim != nil }

    public private(set) weak var parent: DirNode?

    public var id: ObjectIdentifier { ObjectIdentifier(self) }

    public init(
        name: String,
        category: FileCategory,
        reclaim: ReclaimMark?,
        fileBytes: [FileCategory: Int64],
        children: [DirNode]
    ) {
        self.name = name
        self.category = category
        self.reclaim = reclaim
        self.fileBytes = fileBytes
        self.children = children
        self.size = children.reduce(0) { $0 + $1.size } + fileBytes.values.reduce(0, +)
        for child in children { child.parent = self }
    }

    /// Convenience for callers that only have a boolean reclaimable flag —
    /// `MockTree` and tests. `true` synthesizes a generic **medium**-confidence
    /// mark; `false` maps to `nil`. Medium deliberately: a bare boolean carries no
    /// evidence, so it must never fabricate the auto-purge-eligible `.high` tier.
    public convenience init(
        name: String,
        category: FileCategory,
        isReclaimable: Bool,
        fileBytes: [FileCategory: Int64],
        children: [DirNode]
    ) {
        self.init(
            name: name, category: category,
            reclaim: isReclaimable
                ? ReclaimMark(
                    confidence: .medium, signal: .knownName,
                    reason: "reclaimable") : nil,
            fileBytes: fileBytes, children: children)
    }
}
