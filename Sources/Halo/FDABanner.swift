import SwiftUI

/// A dismissible banner shown when Halo lacks Full Disk Access. Without it the
/// scan can't see inside other apps' data and macOS prompts repeatedly; the
/// button deep-links to the System Settings pane where the user grants it.
struct FDABanner: View {
    @Bindable var model: ScanModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.progress)

            VStack(alignment: .leading, spacing: 1) {
                Text("Halo can't see inside other apps' data")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(
                    "Grant Full Disk Access to scan everything and stop the repeated macOS prompts."
                )
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink3)
                .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button(action: model.openFullDiskAccessSettings) {
                Text("Grant Full Disk Access")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 30)
                    .glassEffect(.regular.tint(Palette.progress), in: .rect(cornerRadius: 8))
                    .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button(action: model.dismissFDABanner) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.ink3)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.glass)
            .help("Dismiss — you can still grant access later from Privacy settings")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Palette.bg3)
        .overlay(alignment: .bottom) { Divider().overlay(Palette.line) }
    }
}
