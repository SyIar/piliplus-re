import ChunUI
import SwiftUI

private struct PiliPresentedPageKey: EnvironmentKey {
    static let defaultValue = false
}

private struct PiliReduceTransparencyPreviewKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var piliReduceTransparencyPreview: Bool {
        get { self[PiliReduceTransparencyPreviewKey.self] }
        set { self[PiliReduceTransparencyPreviewKey.self] = newValue }
    }
    var piliPresentedPage: Bool {
        get { self[PiliPresentedPageKey.self] }
        set { self[PiliPresentedPageKey.self] = newValue }
    }
}

/// The native grouped list owns the section outline. Row backgrounds have no
/// independent rounded shape, stroke or glass rim: adjacent rows form one calm
/// material surface, with only the section's outer corners rounded by SwiftUI.
struct PiliGlassRowBackground: View {
    @Environment(\.piliPresentedPage) private var presented
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.piliReduceTransparencyPreview) private var previewReduceTransparency

    var body: some View {
        Group {
            if reduceTransparency || previewReduceTransparency {
                Color.cc.card
            } else if presented {
                Color.cc.card.opacity(0.35)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PiliForm<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        Form {
            content.listRowBackground(PiliGlassRowBackground())
                .listRowSeparatorTint(Color.cc.mutedForeground.opacity(0.16))
        }
        .buttonStyle(.borderless)
        .piliPageChrome()
    }
}

struct PiliList<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        List {
            content.listRowBackground(PiliGlassRowBackground())
                .listRowSeparatorTint(Color.cc.mutedForeground.opacity(0.16))
        }
        .buttonStyle(.borderless)
        .piliPageChrome()
    }
}

struct PiliSelectionList<Selection: Hashable, Content: View>: View {
    @Binding var selection: Set<Selection>
    private let content: Content
    init(selection: Binding<Set<Selection>>, @ViewBuilder content: () -> Content) {
        _selection = selection
        self.content = content()
    }
    var body: some View {
        List(selection: $selection) {
            content.listRowBackground(PiliGlassRowBackground())
                .listRowSeparatorTint(Color.cc.mutedForeground.opacity(0.16))
        }
        .buttonStyle(.borderless)
        .piliPageChrome()
    }
}

private struct PiliPageChrome: ViewModifier {
    @Environment(\.piliPresentedPage) private var presented
    func body(content: Content) -> some View {
        content
            .piliFont(.base)
            .foregroundStyle(Color.cc.foreground)
            .scrollContentBackground(.hidden)
            .background(presented ? Color.clear : Color.cc.background)
            .scrollEdgeEffectStyle(.soft, for: .all)
    }
}

private struct PiliGlassCard: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.piliReduceTransparencyPreview) private var previewReduceTransparency
    @Environment(\.piliPresentedPage) private var presented
    let radius: CGFloat
    func body(content: Content) -> some View {
        if reduceTransparency || previewReduceTransparency {
            content.background(Color.cc.card, in: RoundedRectangle(cornerRadius: radius))
        } else if presented {
            content.background(Color.cc.card.opacity(0.35), in: RoundedRectangle(cornerRadius: radius))
        } else {
            content.ccGlassEffect(.roundedRectangle(radius))
        }
    }
}

extension View {
    func piliPageChrome() -> some View { modifier(PiliPageChrome()) }
    func piliGlassCard(radius: CGFloat = 16) -> some View { modifier(PiliGlassCard(radius: radius)) }
}

struct PiliAppChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .piliFont(.base)
            .foregroundStyle(Color.cc.foreground)
            .buttonStyle(.glass)
            .tint(Color.cc.primary)
    }
}
