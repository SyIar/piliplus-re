import SwiftUI
import ChunUI

struct DynamicForwardUnavailableView: View {
    var body: some View {
        HStack(spacing: 8) {
            PiliIcon(systemName: "exclamationmark.circle")
                .piliFont(.sm).fontWeight(.semibold)
            Text("原动态不可见或已删除")
                .piliFont(.sm)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .piliGlassCard()
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
