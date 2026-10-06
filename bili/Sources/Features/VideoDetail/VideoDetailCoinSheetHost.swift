import SwiftUI
import ChunUI

struct VideoDetailCoinSheetHost: View {
    @PiliDismiss private var dismiss
    @Environment(\.appThemeTintColor) private var appTintColor
    @ObservedObject var viewModel: VideoDetailViewModel
    @State private var selectedCoinCount = 1
    @State private var isSubmitting = false
    @State private var didSucceed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                PiliIcon(systemName: "bitcoinsign.circle.fill", size: 32)
                    .font(.cc.lg).foregroundStyle(appTintColor)
                    .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : didSucceed)
                Text("已投 \(viewModel.interactionState.coinCount) / 2 枚")
                    .font(.cc.base)
                    .foregroundStyle(.secondary)

                Picker("投币数量", selection: $selectedCoinCount) {
                    ForEach(availableCoinCounts, id: \.self) { count in
                        Text("\(count) 枚").tag(count)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 150)
                .clipped()
                .disabled(isSubmitting || availableCoinCounts.isEmpty)

                if let message = viewModel.interactionMessage, !message.isEmpty {
                    Text(message)
                        .font(.cc.sm)
                        .foregroundStyle(Color.cc.destructive)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                Button(action: submit) {
                    Group {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            PiliLabel("投 \(selectedCoinCount) 枚", systemImage: "bitcoinsign.circle.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(appTintColor)
                .controlSize(.large)
                .disabled(isSubmitting || availableCoinCounts.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
            .navigationTitle("投币")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
        }
        .piliPresentationDetents([.height(330)])
        .presentationDragIndicator(.visible)
        .piliInteractiveDismissDisabled(isSubmitting)
        .onAppear {
            viewModel.interactionMessage = nil
            normalizeSelection()
        }
        .onChange(of: remainingCoinCount) { _, _ in
            normalizeSelection()
        }
    }

    private var remainingCoinCount: Int {
        max(0, 2 - viewModel.interactionState.coinCount)
    }

    private var availableCoinCounts: [Int] {
        guard remainingCoinCount > 0 else { return [] }
        return Array(1...remainingCoinCount)
    }

    private func normalizeSelection() {
        selectedCoinCount = min(max(selectedCoinCount, 1), max(remainingCoinCount, 1))
    }

    private func submit() {
        guard !isSubmitting, availableCoinCounts.contains(selectedCoinCount) else { return }
        let coinCount = selectedCoinCount
        isSubmitting = true
        Task { @MainActor in
            let succeeded = await viewModel.addCoin(count: coinCount)
            if succeeded {
                didSucceed = true
                Haptics.success()
                if !reduceMotion { try? await Task.sleep(for: .milliseconds(500)) }
                dismiss()
            }
            isSubmitting = false
        }
    }
}
