import SwiftUI

/// A plain-language overview of the current folder, shown at the top of the rail.
/// It generates itself the moment a scope settles (see `ScanModel.refresh`) and
/// reads like a native part of the app — no controls, no branding, and nothing
/// at all when there's no summary to show.
struct SummaryCard: View {
    var model: ScanModel

    var body: some View {
        switch model.summaryState {
        case .idle:
            EmptyView()
        case .loading:
            // A quiet placeholder so the slot doesn't pop in: the real text
            // crossfades over these grey lines when it arrives.
            card {
                VStack(alignment: .leading, spacing: 7) {
                    Text("A short overview of this folder is on its way.")
                    Text("It points out the biggest space.")
                        .font(.system(size: 12))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.ink)
                .redacted(reason: .placeholder)
            }
            .transition(.opacity)
        case .ready(let insight):
            card { ready(insight) }
                .transition(.opacity)
        }
    }

    private func ready(_ insight: SpaceInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(insight.headline)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !insight.tip.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "leaf")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Palette.reclaim)
                    Text(insight.tip)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Shared card chrome: a glass panel inset to match the rail's rhythm.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13).padding(.vertical, 11)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .padding(.horizontal, 12).padding(.top, 10)
    }
}
