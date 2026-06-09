import Foundation

/// Evidence-based classification of directories and files into `FileCategory`s,
/// and detection of reclaimable directories.
///
/// A directory is flagged reclaimable when there is *evidence* it can be
/// regenerated, in precedence order (strongest first):
///   1. it is a descendant of a reclaim root (attributed to that override);
///   2. a **sibling manifest** rebuilds it (`package.json` ↔ `node_modules`);
///   3. it carries a verified **`CACHEDIR.TAG`** cache marker;
///   4. its name is on the **curated list** (high for unambiguous names, medium
///      for names that could also be real user data).
/// Confidence takes the strongest match; category takes the most specific.
public enum Classifier {

    // MARK: - Evidence passed parent → child

    /// What a parent observed about a child it is creating: a sibling manifest
    /// (if any) that regenerates a directory of the child's name, and the
    /// category that implies.
    public struct Hint: Sendable {
        public let manifest: String?
        public let category: FileCategory?
        public static let none = Hint(manifest: nil, category: nil)
    }

    /// Result of classifying a directory.
    public struct DirClass: Sendable {
        public let category: FileCategory
        /// Override applied to this dir's own files and inherited by every
        /// descendant (`nil` = no override).
        public let filesAs: FileCategory?
        public let reclaim: ReclaimMark?
    }

    // MARK: - Manifest evidence

    private struct ManifestRule {
        let manifest: String        // lowercased filename
        let dirs: Set<String>       // lowercased dir names it regenerates
        let category: FileCategory
    }

    private static let manifestRules: [ManifestRule] = [
        .init(manifest: "package.json",     dirs: ["node_modules"], category: .deps),
        .init(manifest: "package.json",     dirs: ["dist", ".next", "out", ".turbo", ".nuxt", ".svelte-kit", ".parcel-cache"], category: .build),
        .init(manifest: "cargo.toml",       dirs: ["target"], category: .build),
        .init(manifest: "podfile",          dirs: ["pods"], category: .deps),
        .init(manifest: "go.mod",           dirs: ["vendor"], category: .deps),
        .init(manifest: "composer.json",    dirs: ["vendor"], category: .deps),
        // Note: NOT vendor — a Ruby `vendor/` is hand-maintained, checked-in
        // content; `bundle install` regenerates `.bundle`, not `vendor/`.
        .init(manifest: "gemfile",          dirs: [".bundle"], category: .deps),
        .init(manifest: "pyproject.toml",   dirs: [".venv", "venv"], category: .deps),
        .init(manifest: "requirements.txt", dirs: [".venv", "venv"], category: .deps),
        .init(manifest: "setup.py",         dirs: [".venv", "venv"], category: .deps),
        .init(manifest: "pyproject.toml",   dirs: ["__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache"], category: .cache),
        .init(manifest: "build.gradle",     dirs: ["build", ".gradle"], category: .build),
        .init(manifest: "settings.gradle",  dirs: ["build", ".gradle"], category: .build),
        .init(manifest: "pubspec.yaml",     dirs: [".dart_tool", "build"], category: .build),
    ]

    /// The hint for a child named `childName`, given the (lowercased) set of file
    /// names present in the parent directory.
    public static func hint(forChild childName: String, siblings: Set<String>) -> Hint {
        let n = childName.lowercased()
        for rule in manifestRules where rule.dirs.contains(n) && siblings.contains(rule.manifest) {
            return Hint(manifest: rule.manifest, category: rule.category)
        }
        return .none
    }

    // MARK: - Name rules

    struct NameKind {
        let category: FileCategory
        let overridesChildren: Bool
        /// Reclaim confidence if reclaimable by name alone (`nil` = keep).
        let reclaim: ReclaimConfidence?
    }

    static func classifyName(_ name: String) -> NameKind {
        switch name.lowercased() {
        // Unambiguous regenerable dirs — high confidence by name alone.
        case "node_modules", ".venv", "venv", "site-packages", "pods", ".cargo":
            return NameKind(category: .deps, overridesChildren: true, reclaim: .high)
        case "deriveddata", ".next", ".turbo", ".gradle":
            return NameKind(category: .build, overridesChildren: true, reclaim: .high)
        case ".trash":
            return NameKind(category: .trash, overridesChildren: true, reclaim: .high)
        case "wandb", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache":
            return NameKind(category: .cache, overridesChildren: true, reclaim: .high)
        // Ambiguous names — could hold real user data, so medium until something
        // corroborates (a manifest sibling or CACHEDIR.TAG lifts these to high).
        case "build", ".build", "dist", "out", "target":
            return NameKind(category: .build, overridesChildren: true, reclaim: .medium)
        case "caches", "cache", ".cache":
            return NameKind(category: .cache, overridesChildren: true, reclaim: .medium)
        case "vendor":
            return NameKind(category: .deps, overridesChildren: true, reclaim: .medium)
        // Non-reclaimable categories.
        case "containers":
            // Category-only, NOT an override: an app sandbox container holds its
            // own regenerable caches (`Data/Library/Caches`). Forcing `.container`
            // on the whole subtree would bucket those as un-reclaimable container
            // data and hide them — so classify each descendant on its own evidence.
            return NameKind(category: .container, overridesChildren: false, reclaim: nil)
        case "docker":
            return NameKind(category: .container, overridesChildren: true, reclaim: nil)
        case "movies", "music", "pictures", "photos":
            return NameKind(category: .media, overridesChildren: true, reclaim: nil)
        case "documents", "notes":
            return NameKind(category: .docs, overridesChildren: false, reclaim: nil)
        case "applications":
            return NameKind(category: .app, overridesChildren: true, reclaim: nil)
        case "library", "application support":
            return NameKind(category: .other, overridesChildren: false, reclaim: nil)
        case "projects", "developer", "code", "src", "repos", ".git":
            return NameKind(category: .code, overridesChildren: false, reclaim: nil)
        default:
            return NameKind(category: .other, overridesChildren: false, reclaim: nil)
        }
    }

    /// The category a name imposes on its descendants (`nil` if it doesn't
    /// override). Cheap and name-only — lets the scanner bucket a dir's files
    /// before its full (contents-dependent) classification is known.
    static func nameOverride(_ name: String) -> FileCategory? {
        let k = classifyName(name)
        return k.overridesChildren ? k.category : nil
    }

    // MARK: - Final classification

    /// Finalize a directory's classification from its name, the hint its parent
    /// passed, the inherited override (if under a reclaim root), and whether it
    /// contains a verified `CACHEDIR.TAG`.
    public static func classify(name: String,
                                inherited: FileCategory?,
                                hint: Hint,
                                hasCachedirTag: Bool,
                                parent: String? = nil) -> DirClass {
        // Descendant of a reclaim root: attributed to the override, never its own
        // separate target.
        if let inherited {
            return DirClass(category: inherited, filesAs: inherited, reclaim: nil)
        }
        // Manifest evidence — strongest, most specific category.
        if let manifest = hint.manifest, let cat = hint.category {
            return DirClass(category: cat, filesAs: cat,
                            reclaim: ReclaimMark(confidence: .high, signal: .manifest(manifest),
                                                 reason: "regenerable — \(manifest) is alongside it"))
        }
        // Verified cache marker.
        if hasCachedirTag {
            return DirClass(category: .cache, filesAs: .cache,
                            reclaim: ReclaimMark(confidence: .high, signal: .cachedirTag,
                                                 reason: "marked as a cache (CACHEDIR.TAG)"))
        }
        // Curated name fallback.
        let k = classifyName(name)
        // A `Caches` sitting directly under a `Library` is *the* macOS cache root
        // (`~/Library/Caches`, and every app sandbox container's
        // `Data/Library/Caches`) — an unambiguous, system-rebuilt location. That
        // context lifts the bare name's medium to high.
        let isSystemCacheRoot = parent?.lowercased() == "library"
            && ["caches", "cache", ".cache"].contains(name.lowercased())
        let mark = k.reclaim.map { conf in
            isSystemCacheRoot
                ? ReclaimMark(confidence: .high, signal: .knownName,
                              reason: "macOS cache directory (Library/Caches) — the system rebuilds it")
                : ReclaimMark(confidence: conf, signal: .knownName,
                              reason: "known \(k.category.label.lowercased()) directory")
        }
        return DirClass(category: k.category,
                        filesAs: k.overridesChildren ? k.category : nil,
                        reclaim: mark)
    }

    // MARK: - Files

    /// Classify a file by its (lowercased, no-dot) extension.
    public static func classifyFile(ext: String) -> FileCategory {
        switch ext {
        case "mp4", "mov", "mkv", "avi", "m4v", "webm",
             "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "raw", "psd",
             "mp3", "wav", "flac", "aac", "m4a", "aiff":
            return .media
        case "swift", "ts", "tsx", "js", "jsx", "mjs", "py", "rs", "go", "rb", "php",
             "c", "cc", "cpp", "h", "hpp", "java", "kt", "cs", "scala", "sh", "lua",
             "html", "css", "scss", "json", "yaml", "yml", "toml", "xml", "sql":
            return .code
        case "pdf", "doc", "docx", "pages", "txt", "md", "rtf", "key", "numbers",
             "xls", "xlsx", "ppt", "pptx", "csv", "epub", "tex":
            return .docs
        case "app":
            return .app
        default:
            return .other
        }
    }
}
