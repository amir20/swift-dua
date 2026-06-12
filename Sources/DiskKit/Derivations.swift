import Foundation

/// Pure tree derivations, ported from the design's `dial-app.jsx`: the two
/// lenses (folder vs. type), reclaimable accounting, and path helpers.
public enum Derive {

    // MARK: - Reclaimable

    /// Reclaimable bytes within a subtree. A reclaimable directory contributes
    /// its whole size; otherwise we sum reclaimable descendants.
    public static func reclaimBytes(_ n: DirNode) -> Int64 {
        n.isReclaimable ? n.size : n.children.reduce(0) { $0 + reclaimBytes($1) }
    }

    /// The maximal reclaimable directories in a subtree (each "safe target").
    public static func reclaimRoots(_ n: DirNode) -> [DirNode] {
        n.isReclaimable ? [n] : n.children.flatMap { reclaimRoots($0) }
    }

    // MARK: - Type lens

    /// Leaf-accurate size of every category within a subtree.
    public static func typeSizes(_ root: DirNode) -> [FileCategory: Int64] {
        var acc: [FileCategory: Int64] = [:]
        func walk(_ n: DirNode) {
            for (c, b) in n.fileBytes { acc[c, default: 0] += b }
            n.children.forEach(walk)
        }
        walk(root)
        return acc
    }

    /// Reclaimable bytes per category (grouped by each reclaim root's category).
    public static func typeReclaim(_ root: DirNode) -> [FileCategory: Int64] {
        var out: [FileCategory: Int64] = [:]
        for r in reclaimRoots(root) { out[r.category, default: 0] += r.size }
        return out
    }

    /// Where a category lives: the maximal same-category directories in the
    /// subtree, sorted by size descending.
    public static func typeLocations(
        _ root: DirNode, _ cat: FileCategory
    ) -> [(node: DirNode, size: Int64, recl: Int64)] {
        var result: [(node: DirNode, size: Int64, recl: Int64)] = []
        func walk(_ n: DirNode) {
            if n !== root, n.category == cat, n.parent?.category != cat {
                result.append((n, n.size, reclaimBytes(n)))
                return  // this whole subtree is the location; don't descend further
            }
            n.children.forEach(walk)
        }
        walk(root)
        return result.sorted { $0.size > $1.size }
    }

    // MARK: - Pruning

    /// The tree with the given nodes (matched by identity) removed: every
    /// ancestor of a removed node is rebuilt — `DirNode.init` recomputes its
    /// subtree size — while untouched subtrees are shared with the old tree
    /// (and re-parented into the new one; the old tree is dead after this).
    /// Returns the **same instance** when nothing matched, so a caller holding
    /// possibly-stale node identities can detect the miss, and `nil` when the
    /// root itself was removed.
    public static func removing(_ ids: Set<ObjectIdentifier>, from root: DirNode) -> DirNode? {
        guard !ids.isEmpty else { return root }
        if ids.contains(root.id) { return nil }
        var changed = false
        var kept: [DirNode] = []
        kept.reserveCapacity(root.children.count)
        for child in root.children {
            if let result = removing(ids, from: child) {
                if result !== child { changed = true }
                kept.append(result)
            } else {
                changed = true
            }
        }
        guard changed else { return root }
        return DirNode(
            name: root.name, category: root.category, reclaim: root.reclaim,
            fileBytes: root.fileBytes, children: kept)
    }

    // MARK: - Path

    /// Ancestor chain from the tree root down to `n` (inclusive).
    public static func pathTo(_ n: DirNode) -> [DirNode] {
        var chain: [DirNode] = []
        var x: DirNode? = n
        while let node = x {
            chain.insert(node, at: 0)
            x = node.parent
        }
        return chain
    }
}
