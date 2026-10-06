import SwiftUI
import ChunUI

struct LibraryLoadingRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .piliFont(.base)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

struct LibraryLoadMoreTriggerRow: View {
    let title: String
    let loadMore: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            PiliIcon(systemName: "arrow.down.circle")
            Text(title)
        }
        .piliFont(.sm)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onAppear(perform: loadMore)
    }
}

struct LibraryErrorRow: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PiliLabel(title, systemImage: "exclamationmark.circle")
                .piliFont(.base).fontWeight(.semibold)
                .foregroundStyle(Color.cc.warning)

            Text(message)
                .piliFont(.sm)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Button(action: retry) {
                PiliLabel("重试", systemImage: "arrow.clockwise")
                    .piliFont(.sm).fontWeight(.semibold)
            }
            .buttonStyle(.glass)
        }
        .padding(.vertical, 6)
    }
}
