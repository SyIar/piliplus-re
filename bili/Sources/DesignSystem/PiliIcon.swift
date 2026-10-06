import ChunUI
import SwiftUI

/// Uses ChunUI's bundled Pika glyphs while inheriting the control's foreground
/// style (including white media controls and disabled/selected states).
struct PiliIcon: View {
    let systemName: String
    var size: CGFloat = 18
    private var stretches = false

    nonisolated init(systemName: String, size: CGFloat = 18) { self.systemName = systemName; self.size = size }
    var body: some View {
        Group {
            if stretches {
                GeometryReader { proxy in glyph(size: min(proxy.size.width, proxy.size.height)).frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else { glyph(size: size) }
        }
        .accessibilityHidden(true)
    }
    private func glyph(size: CGFloat) -> some View {
        Rectangle().fill(.foreground)
            .frame(width: size, height: size)
            .mask { PikaIcon(PiliSymbols.pika(systemName), size: size, color: .white) }
    }
    func resizable() -> Self { var copy = self; copy.stretches = true; return copy }
}

struct PiliLabel: View {
    let title: String
    let systemImage: String
    nonisolated init(_ title: String, systemImage: String) { self.title = title; self.systemImage = systemImage }
    var body: some View {
        Label { Text(title) } icon: { PiliIcon(systemName: systemImage) }
    }
}

struct PiliIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    let role: ButtonRole?
    init(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.role = role; self.action = action
    }
    var body: some View { Button(role: role, action: action) { PiliLabel(title, systemImage: systemImage) } }
}

struct PiliUnavailableView: View {
    let title: String
    let systemImage: String
    var description: Text?
    init(_ title: String, systemImage: String, description: Text? = nil) {
        self.title = title; self.systemImage = systemImage; self.description = description
    }
    var body: some View {
        ContentUnavailableView {
            Label { Text(title).piliFont(.baseBold) } icon: { PiliIcon(systemName: systemImage, size: 44) }
        } description: {
            description?.piliFont(.sm).foregroundStyle(Color.cc.mutedForeground)
        }
    }
}
