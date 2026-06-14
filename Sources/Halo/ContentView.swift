import AppKit
import DiskKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: ScanModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: model)
            if model.showFDABanner {
                FDABanner(model: model)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            HStack(spacing: 0) {
                stage
                RailView(model: model)
            }
        }
        .background(Palette.bg)
        .frame(minWidth: 980, minHeight: 660)
        // Re-probe Full Disk Access whenever the app comes forward — the user may
        // have just granted it in System Settings — and animate the banner away.
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            model.refreshFullDiskAccess()
        }
    }

    private var stage: some View {
        ZStack {
            RadialGradient(
                colors: [Palette.bg, Palette.bg2],
                center: .init(x: 0.5, y: 0.42),
                startRadius: 0, endRadius: 380)

            if model.root != nil {
                DonutView(model: model)
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Two-finger swipe left over the donut goes back to the enclosing folder,
        // mirroring the chevron-left back button (⌘↑). Lives behind the donut so
        // the slices keep their hover/tap handling.
        .background(SwipeBackView { model.back() })
    }
}

#Preview {
    let model = ScanModel()
    model.load(MockTree.make())
    return ContentView(model: model)
        .frame(width: 1180, height: 760)
}
