/// Why a directory is considered reclaimable, and how sure we are — carried on
/// every reclaim target so a future move-to-Trash flow can require strong
/// evidence and explain itself.
///
/// Detection is evidence-based (see `Classifier`): a directory is flagged when
/// there is a reason it can be regenerated, not merely because its name is on a
/// list. The strongest signals are a verified cache marker or a sibling manifest
/// that rebuilds it; a curated name match is the weaker fallback.

/// What evidence flagged a directory.
public enum ReclaimSignal: Sendable, Equatable {
    /// The directory contains a verified `CACHEDIR.TAG` (the cross-platform cache
    /// marker — written by Cargo, honored by backup tools).
    case cachedirTag
    /// A sibling manifest regenerates this directory, e.g. `package.json` next to
    /// `node_modules`. The associated value is the manifest's filename.
    case manifest(String)
    /// Matched the curated list of known regenerable directory names.
    case knownName
}

/// How safe-to-purge the evidence makes a directory. A future delete gate can
/// require `.high`; `.medium` is shown but not auto-purged.
public enum ReclaimConfidence: Sendable, Equatable {
    case high
    case medium
}

/// A directory's reclaimability, or `nil` when it should be kept.
public struct ReclaimMark: Sendable, Equatable {
    public let confidence: ReclaimConfidence
    public let signal: ReclaimSignal
    /// Human-readable justification, for the purge UI.
    public let reason: String

    public init(confidence: ReclaimConfidence, signal: ReclaimSignal, reason: String) {
        self.confidence = confidence
        self.signal = signal
        self.reason = reason
    }
}
