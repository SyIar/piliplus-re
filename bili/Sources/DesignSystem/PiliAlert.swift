import ChunUI
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

/// One app-owned confirmation at a time, presented by ChunUI's public card API.
/// Keep the source target alive until the chosen action has run; dismissal alone
/// must never execute an action or clear the target before a deletion reads it.
@MainActor
final class PiliAlertSession: ObservableObject {
    private static var active: PiliAlertSession?
    private var requestID: UUID?
    private var isClosing = false
    private var onClose: (() -> Void)?

    static func present(title: String, message: String = "", actions: [PiliAlertButton]) {
        let session = PiliAlertSession()
        session.present(title: title, message: message, actions: actions, onClose: {})
    }

    func present(title: String, message: String, actions: [PiliAlertButton], onClose: @escaping () -> Void) {
        guard requestID == nil else { return }
        Self.active?.dismiss()
        let token = UUID()
        requestID = token
        isClosing = false
        self.onClose = onClose
        Self.active = self
        let card = PiliConfirmationCard(title: title, message: message, actions: actions) { [weak self] action in
            guard let self, requestID == token, !isClosing else { return }
            isClosing = true
            AppHelper.shared.dismissCenterCard {
                guard self.requestID == token else { return }
                action.action()
                self.finish(token)
            }
        }
        .onDisappear { [weak self] in
            guard let self, !isClosing else { return }
            finish(token)
        }
        AppHelper.shared.showCenterCard(view: PiliPresentationRoot(content: card, isSheet: false))
    }

    func dismiss() {
        guard let token = requestID, !isClosing else { return }
        isClosing = true
        if Self.active === self { AppHelper.shared.dismissCenterCard(animated: false) }
        finish(token)
    }

    private func finish(_ token: UUID) {
        guard requestID == token else { return }
        if Self.active === self { Self.active = nil }
        requestID = nil
        isClosing = false
        let close = onClose; onClose = nil; close?()
    }
}

private struct PiliConfirmationCard: View {
    let title: String
    let message: String
    let actions: [PiliAlertButton]
    let select: (PiliAlertButton) -> Void
    @ScaledMetric(relativeTo: .body) private var buttonHeight = 48

    private var viewport: CGSize {
        AppHelper.shared.topMostViewController()?.view.window?.bounds.size ?? CGSize(width: 390, height: 844)
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            contents
            ScrollView { contents }.scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: min(360, viewport.width * 0.86))
        .frame(maxHeight: viewport.height * 0.8)
        .fixedSize(horizontal: false, vertical: true)
        .piliGlassCard(radius: 24)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityIdentifier("pili.confirmation")
    }

    private var contents: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).piliFont(.baseBold).accessibilityAddTraits(.isHeader)
            if !message.isEmpty {
                Text(message).piliFont(.sm).foregroundStyle(Color.cc.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 10) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button(role: action.role) { select(action) } label: {
                        Text(action.title).piliFont(.baseBold)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(action.role == .cancel ? Color.cc.foreground : .white)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .frame(maxWidth: .infinity, minHeight: buttonHeight)
                            .ccNeoChrome(action.role == .cancel ? .secondary : .primary,
                                         height: buttonHeight, accent: Color.cc.primary)
                    }
                    .buttonStyle(CCNeoPressStyle())
                }
            }
        }
        .padding(24)
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
