import Foundation

/// A representative mock home folder, ported from the design's `ledger-data.jsx`.
/// Used for SwiftUI previews and tests so the UI and derivations can be exercised
/// without a real scan.
public enum MockTree {
    private static let GB: Int64 = 1_073_741_824

    private static func d(
        _ name: String, _ cat: FileCategory,
        recl: Bool = false,
        files: [FileCategory: Int64] = [:],
        _ kids: [DirNode] = []
    ) -> DirNode {
        DirNode(name: name, category: cat, isReclaimable: recl, fileBytes: files, children: kids)
    }

    public static func make() -> DirNode {
        let projects = d(
            "Projects", .code,
            [
                d(
                    "acme-dashboard", .code,
                    [
                        d("node_modules", .deps, recl: true, files: [.deps: 8 * GB]),
                        d(".next", .build, recl: true, files: [.build: 3 * GB]),
                        d(".git", .code, files: [.code: 5 * GB]),
                        d("src", .code, files: [.code: 1 * GB, .media: 1 * GB]),
                    ]),
                d(
                    "legacy-api", .code,
                    [
                        d("node_modules", .deps, recl: true, files: [.deps: 6 * GB]),
                        d("dist", .build, recl: true, files: [.build: 1 * GB]),
                        d(".git", .code, files: [.code: 3 * GB]),
                    ]),
                d(
                    "ml-experiments", .code,
                    [
                        d("checkpoints", .other, files: [.other: 15 * GB]),
                        d(".venv", .deps, recl: true, files: [.deps: 4 * GB]),
                        d("wandb", .cache, recl: true, files: [.cache: 2 * GB]),
                    ]),
            ])

        let library = d(
            "Library", .other,
            [
                d("Caches", .cache, recl: true, files: [.cache: 11 * GB]),
                d("Application Support", .other, files: [.app: 24 * GB]),
                d(
                    "Developer", .build,
                    [
                        d("DerivedData", .build, recl: true, files: [.build: 16 * GB])
                    ]),
                d("Containers", .container, files: [.container: 6 * GB]),
            ])

        let docker = d(
            "Docker", .container,
            [
                d("images", .container, files: [.container: 38 * GB]),
                d("volumes", .container, files: [.container: 16 * GB]),
                d("build cache", .build, recl: true, files: [.build: 9 * GB]),
            ])

        let movies = d("Movies", .media, files: [.media: 41 * GB])
        let downloads = d("Downloads", .other, files: [.other: 28 * GB])
        let documents = d("Documents", .docs, files: [.docs: 19 * GB])
        let applications = d("Applications", .app, files: [.app: 13 * GB])
        let music = d("Music", .media, files: [.media: 8 * GB])
        let trash = d(".Trash", .trash, recl: true, files: [.trash: 5 * GB])
        let desktop = d("Desktop", .other, files: [.other: 3 * GB])

        return d(
            "alex", .other,
            files: [.other: 1 * GB],
            [
                projects, library, docker, movies, downloads,
                documents, applications, music, trash, desktop,
            ])
    }
}
