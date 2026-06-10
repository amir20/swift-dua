import SwiftUI

struct HeaderView: View {
    @Bindable var model: ScanModel

    var body: some View {
        HStack(spacing: 12) {
            Button(action: model.back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)
            .disabled(model.path.count <= 1)
            .opacity(model.path.count <= 1 ? 0.36 : 1)

            crumbs

            Spacer(minLength: 12)

            Button(action: model.openInFinder) {
                Label("Open in Finder", systemImage: "folder")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
            }
            .buttonStyle(.glass)
            .help("Open this folder in Finder")

            segmented
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Divider().overlay(Palette.line) }
    }

    private var crumbs: some View {
        HStack(spacing: 5) {
            ForEach(Array(model.crumbs.enumerated()), id: \.offset) { i, c in
                let last = i == model.crumbs.count - 1
                Text(c)
                    .font(.system(size: 13, weight: last ? .semibold : .medium,
                                  design: i > 0 ? .monospaced : .default))
                    .foregroundStyle(last ? Palette.ink : Palette.ink3)
                    .onTapGesture { if !last && i > 0 { model.goTo(crumb: i) } }
                if !last {
                    Text("›").font(.system(size: 12)).foregroundStyle(Palette.ink4)
                }
            }
        }
    }

    private var segmented: some View {
        // A glass track; the selected segment lifts as its own interactive glass
        // pill, the two morphing fluidly inside the shared container.
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                segButton("By folder", .folder)
                segButton("By type", .type)
            }
        }
        .padding(2)
        .glassEffect(.regular, in: .rect(cornerRadius: 9))
    }

    private func segButton(_ title: String, _ lens: Lens) -> some View {
        let on = model.mode == lens
        return Text(title)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(on ? Palette.ink : Palette.ink3)
            .padding(.horizontal, 13).padding(.vertical, 5)
            .glassEffect(on ? .regular.interactive() : .identity, in: .rect(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { model.setMode(lens) }
    }
}
