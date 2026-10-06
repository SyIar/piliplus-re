import SwiftUI
import ChunUI

struct SettingsNavigationRow: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 13) {
            PiliIcon(systemName: systemImage, size: 19)
                .piliFont(.base)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(appTintColor)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appTypography(.settingsRow, fallback: .subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .appTypography(.settingsSubtitle, fallback: .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct MineSettingsLabel: View {
    let title: String

    init(_ title: String, systemImage _: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
    }
}

struct PlainSettingsNavigationRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .appTypography(.settingsRow, fallback: .subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .appTypography(.settingsSubtitle, fallback: .caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct MinePlaybackPreferenceChip: View {
    let title: String

    init(title: String, systemImage _: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .appTypography(.badge, fallback: .caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .ccGlassEffect(.capsule)
            .overlay {
                Capsule()
                    .stroke(Color(uiColor: .separator).opacity(0.10), lineWidth: 0.5)
            }
    }
}

/// Keep a menu picker in the trailing column even when its explanation wraps.
/// Native Form pickers move the value below a multiline label on narrow screens.
struct PiliSettingPicker<Selection: Hashable, Options: View, Label: View>: View {
    @Binding private var selection: Selection
    private let options: Options
    private let label: Label

    init(selection: Binding<Selection>, @ViewBuilder content: () -> Options, @ViewBuilder label: () -> Label) {
        _selection = selection; options = content(); self.label = label()
    }

    init(_ title: String, selection: Binding<Selection>, @ViewBuilder content: () -> Options) where Label == Text {
        _selection = selection; options = content(); label = Text(title)
    }

    var body: some View {
        HStack(spacing: 16) {
            label.frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Picker(selection: $selection) { options } label: { label }
                .labelsHidden().pickerStyle(.menu)
                .lineLimit(1).layoutPriority(1)
        }
    }
}

struct PiliSettingAction<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: 16) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
    }
}
