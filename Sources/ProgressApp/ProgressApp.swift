import SwiftUI
import AppKit

@main
struct ProgressApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Progress Demo") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

/// Makes the SwiftPM executable behave like a normal foreground app:
/// shows in the Dock, takes focus on launch, and quits when the window closes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        true
    }
}

struct ContentView: View {
    @State private var progress: Double = 0
    @State private var isRunning = false

    /// How long a full 0 -> 100% run takes, and how often we update.
    private let duration: Double = 2.0
    private let tickInterval: Double = 0.02

    var body: some View {
        VStack(spacing: 28) {
            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 320)

            Button(isRunning ? "Running…" : "Start") {
                start()
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(isRunning)
            .keyboardShortcut(.defaultAction)
        }
        .padding(48)
        .frame(minWidth: 420, minHeight: 280)
    }

    private func start() {
        progress = 0
        isRunning = true

        let increment = tickInterval / duration
        Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { timer in
            withAnimation(.linear(duration: tickInterval)) {
                progress = min(1.0, progress + increment)
            }
            if progress >= 1.0 {
                timer.invalidate()
                isRunning = false
            }
        }
    }
}
