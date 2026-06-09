import Foundation

/// Moves reclaimable directories to the Trash. The only piece that touches the
/// filesystem destructively — kept tiny and UI-free so the dialog and model can
/// be reasoned about (and tested) separately.
enum Reclaimer {
    /// Move each URL to the Trash, continuing past failures (a permission- or
    /// SIP-protected item shouldn't abort the rest of the batch). Returns what
    /// was trashed and what failed, so the caller can report partial results.
    static func moveToTrash(_ urls: [URL]) -> (trashed: [URL], failed: [(url: URL, error: Error)]) {
        var trashed: [URL] = []
        var failed: [(url: URL, error: Error)] = []
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashed.append(url)
            } catch {
                failed.append((url, error))
            }
        }
        return (trashed, failed)
    }
}
