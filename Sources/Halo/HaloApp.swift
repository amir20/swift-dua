import AppKit
import Combine
import DiskKit
import Sparkle
import SwiftUI

@main
struct HaloApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = ScanModel()

    /// Sparkle auto-updater. Only started when running from a real .app
    /// bundle — `swift run` and the test runner execute a bare binary that
    /// Sparkle can't update (no Info.plist feed URL, nothing to replace).
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: Bundle.main.bundleURL.pathExtension == "app",
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup("Halo") {
            ContentView(model: model)
                .onAppear {
                    if model.root == nil {
                        let home = FileManager.default.homeDirectoryForCurrentUser.path
                        model.scan(path: home)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updaterController.updater)
            }
        }
    }
}

/// "Check for Updates…" menu item, disabled while Sparkle can't start a check
/// (updater not started, or a check is already in flight).
private struct CheckForUpdatesButton: View {
    let updater: SPUUpdater
    @State private var canCheck = false

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!canCheck)
            .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheck = $0 }
    }
}

/// Makes the SwiftPM executable behave like a normal foreground app:
/// shows in the Dock and takes focus on launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}
