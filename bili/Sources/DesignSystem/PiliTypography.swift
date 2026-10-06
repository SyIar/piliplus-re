import ChunUI
import SwiftUI

/// ChunUI's 13/17/24 baseline, scaled with the user's system or app text size.
/// Package tokens are fixed point sizes, so app text opts into Dynamic Type here.
enum PiliTextStyle {
    case sm, smBold, base, baseBold, lg, lgBold
    var bold: Bool { self == .smBold || self == .baseBold || self == .lgBold }
}

private struct PiliTypography: ViewModifier {
    let style: PiliTextStyle
    @ScaledMetric(relativeTo: .caption) private var small = 13.0
    @ScaledMetric(relativeTo: .body) private var base = 17.0
    @ScaledMetric(relativeTo: .title2) private var large = 24.0
    func body(content: Content) -> some View {
        let size = switch style {
        case .sm, .smBold: small
        case .base, .baseBold: base
        case .lg, .lgBold: large
        }
        content.font(.cc.custom(size, bold: style.bold))
    }
}

extension View {
    func piliFont(_ style: PiliTextStyle) -> some View { modifier(PiliTypography(style: style)) }
}
