/// A file/disk-usage category. The donut colors and the "by type" lens are
/// keyed on these. Order is the canonical display order.
public enum FileCategory: String, CaseIterable, Sendable, Hashable {
    case deps
    case cache
    case build
    case container
    case media
    case code
    case docs
    case app
    case trash
    case other

    /// Human-readable label shown in the rail and donut hole.
    public var label: String {
        switch self {
        case .deps: return "Dependencies"
        case .cache: return "Caches"
        case .build: return "Build output"
        case .container: return "Containers"
        case .media: return "Media"
        case .code: return "Source code"
        case .docs: return "Documents"
        case .app: return "Applications"
        case .trash: return "Trash"
        case .other: return "Other"
        }
    }
}
