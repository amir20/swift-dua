import DiskKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: ScanModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: model)
            HStack(spacing: 0) {
                stage
                RailView(model: model)
            }
        }
        .background(Palette.bg)
        .frame(minWidth: 980, minHeight: 660)
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
    }
}

#Preview {
    let model = ScanModel()
    model.load(MockTree.make())
    return ContentView(model: model)
        .frame(width: 1180, height: 760)
}
