import SwiftUI

/// One glass surface per group of floating controls; content uses quiet material.
struct PiliLiquidGlassSurface<S: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.piliReduceTransparencyPreview) private var previewReduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let shape: S
    var overVideo = false
    var interactive = false

    private var dark: Bool { overVideo || colorScheme == .dark }

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency || previewReduceTransparency {
                content.background(dark ? Color(white: 0.12) : Color(white: 0.96), in: shape)
            } else if overVideo {
                content.glassEffect(
                    .clear.tint(.black.opacity(0.22))
                        .interactive(interactive),
                    in: shape
                )
            } else {
                content.glassEffect(.regular.interactive(interactive), in: shape)
            }
        }
        .overlay {
            if contrast == .increased {
                shape.strokeBorder(dark ? .white.opacity(0.7) : .black.opacity(0.4), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func piliLiquidGlass<S: InsettableShape>(in shape: S, overVideo: Bool = false, interactive: Bool = false) -> some View {
        modifier(PiliLiquidGlassSurface(shape: shape, overVideo: overVideo, interactive: interactive))
    }
}

struct PiliGlassPlayerButton: View {
    let symbol: String
    let title: String
    var size: CGFloat = 44
    var prominent = false
    var grouped = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PiliIcon(systemName: symbol, size: prominent ? 28 : (size > 44 ? 26 : 22))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .modifier(PiliGlassPlayerButtonSurface(grouped: grouped))
        .accessibilityLabel(title)
    }
}

private struct PiliGlassPlayerButtonSurface: ViewModifier {
    let grouped: Bool
    func body(content: Content) -> some View {
        if grouped { content } else { content.piliLiquidGlass(in: Circle(), overVideo: true, interactive: true) }
    }
}
