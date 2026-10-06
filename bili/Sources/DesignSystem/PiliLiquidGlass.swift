import SwiftUI

/// Clear floating controls above media; content cards keep their own solid surface.
struct PiliLiquidGlassSurface<S: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let shape: S
    var overVideo = false
    var interactive = false

    private var dark: Bool { overVideo || colorScheme == .dark }

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content.background(dark ? Color(white: 0.12) : Color(white: 0.96), in: shape)
            } else {
                content.glassEffect(
                    .clear.tint(dark ? .black.opacity(0.18) : .white.opacity(0.22))
                        .interactive(interactive),
                    in: shape
                )
            }
        }
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(contrast == .increased ? 0.7 : (dark ? 0.32 : 0.7)),
                        .white.opacity(0.06),
                        .white.opacity(dark ? 0.18 : 0.42)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing
                ), lineWidth: contrast == .increased ? 1 : 0.6
            )
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(dark ? 0.2 : 0.08), radius: 12, y: 5)
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
            PiliIcon(systemName: symbol, size: prominent ? 28 : 18)
                .font(.system(size: prominent ? 28 : 18, weight: .medium))
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
