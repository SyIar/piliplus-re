import ChunUI
import Combine
import SwiftUI

struct PiliAlertButton {
    let title: String
    let role: ButtonRole?
    let action: @MainActor () -> Void
    init(_ title: String, role: ButtonRole? = nil, action: @escaping @MainActor () -> Void = {}) {
        self.title = title; self.role = role; self.action = action
    }
}

@resultBuilder
enum PiliAlertBuilder {
    static func buildExpression(_ action: PiliAlertButton) -> [PiliAlertButton] { [action] }
    static func buildBlock(_ actions: [PiliAlertButton]...) -> [PiliAlertButton] { actions.flatMap { $0 } }
    static func buildOptional(_ actions: [PiliAlertButton]?) -> [PiliAlertButton] { actions ?? [] }
    static func buildEither(first: [PiliAlertButton]) -> [PiliAlertButton] { first }
    static func buildEither(second: [PiliAlertButton]) -> [PiliAlertButton] { second }
    static func buildArray(_ actions: [[PiliAlertButton]]) -> [PiliAlertButton] { actions.flatMap { $0 } }
}

/// Preserves the source binding until ChunUI has performed the selected action.
/// CCAlertCenter dismisses first and invokes handlers after its exit transition.
@MainActor
final class PiliAlertSession: ObservableObject {
    private var requestID: UUID?
    private var observer: AnyCancellable?
    private var cleanup: Task<Void, Never>?
    private var onClose: (() -> Void)?

    func present(title: String, message: String, actions: [PiliAlertButton], onClose: @escaping () -> Void) {
        guard requestID == nil else { return }
        self.onClose = onClose
        let mapped = actions.map { action in
            CCAlertAction(title: action.title,
                role: action.role == .destructive ? .destructive : action.role == .cancel ? .secondary : .default) { [weak self] in
                guard let self, requestID != nil else { return }
                action.action()
                finish()
            }
        }
        AppHelper.shared.showBottomAlert(title: title, message: message.isEmpty ? nil : message, actions: mapped)
        requestID = CCAlertCenter.shared.current?.id
        observer = CCAlertCenter.shared.$current.sink { [weak self] request in
            guard let self, let requestID, request?.id != requestID else { return }
            cleanup?.cancel()
            cleanup = Task { @MainActor [weak self] in
                // The pinned ChunUI revision dispatches a selected action at 180 ms.
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                self?.finish()
            }
        }
    }

    func dismiss() {
        if requestID == CCAlertCenter.shared.current?.id, requestID != nil { CCAlertCenter.shared.dismiss() }
        finish()
    }

    private func finish() {
        guard requestID != nil else { return }
        requestID = nil; observer = nil; cleanup?.cancel(); cleanup = nil
        let close = onClose; onClose = nil; close?()
    }
}

private struct PiliAlertModifier: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let confirmation: Bool
    let actions: () -> [PiliAlertButton]
    let message: () -> String
    @StateObject private var session = PiliAlertSession()

    func body(content: Content) -> some View {
        content.onChange(of: isPresented, initial: true) { _, shown in
            if shown {
                var choices = actions()
                if !choices.contains(where: { $0.role == .cancel }),
                   confirmation || choices.contains(where: { $0.role == .destructive }) {
                    choices.append(PiliAlertButton("取消", role: .cancel))
                }
                session.present(title: title, message: message(), actions: choices) { isPresented = false }
            } else { session.dismiss() }
        }
    }
}

extension View {
    func piliAlert(_ title: String, isPresented: Binding<Bool>,
        @PiliAlertBuilder actions: @escaping () -> [PiliAlertButton], message: @escaping () -> String = { "" }) -> some View {
        modifier(PiliAlertModifier(title: title, isPresented: isPresented, confirmation: false, actions: actions, message: message))
    }

    func piliConfirmation(_ title: String, isPresented: Binding<Bool>, titleVisibility _: Visibility = .automatic,
        @PiliAlertBuilder actions: @escaping () -> [PiliAlertButton], message: @escaping () -> String = { "" }) -> some View {
        modifier(PiliAlertModifier(title: title, isPresented: isPresented, confirmation: true, actions: actions, message: message))
    }
}
