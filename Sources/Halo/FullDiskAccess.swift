import AppKit
import Foundation

/// Detecting and requesting macOS Full Disk Access for the (non-sandboxed) app.
///
/// Halo walks the whole home tree, descending into other apps' data under
/// `~/Library` (Containers, Group Containers, Application Support). Without Full
/// Disk Access, macOS gates each of those with a per-app "would like to access
/// data from other apps" prompt — and because the parallel walk hits a different
/// container first on each run, that prompt recurs endlessly. Full Disk Access is
/// the system's intended exemption for disk tools: granted once, the prompts stop
/// and the scan sees everything.
enum FullDiskAccess {
    /// Whether this app currently holds Full Disk Access.
    ///
    /// Probes by trying to open the user's TCC database — a file present on every
    /// Mac that is readable *only* with Full Disk Access. A hard permission error
    /// (`EPERM`/`EACCES`) is the single signal that means "denied"; any other
    /// outcome (including the file being absent) is treated as granted so we never
    /// nag on a false negative.
    static var isGranted: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let probe = "\(home)/Library/Application Support/com.apple.TCC/TCC.db"
        let fd = open(probe, O_RDONLY)
        if fd >= 0 {
            close(fd)
            return true
        }
        return !(errno == EPERM || errno == EACCES)
    }

    /// Deep link to System Settings → Privacy & Security → Full Disk Access.
    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// Opens the Full Disk Access settings pane so the user can add Halo.
    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}
