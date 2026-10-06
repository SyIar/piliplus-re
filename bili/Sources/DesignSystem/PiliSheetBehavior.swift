import SwiftUI
import UIKit

nonisolated enum PiliSheetDetent: Hashable, Sendable {
    case medium, large, fraction(CGFloat), height(CGFloat)
    var identifier: UISheetPresentationController.Detent.Identifier {
        switch self {
        case .medium: .medium
        case .large: .large
        case .fraction(let value): .init("pili.fraction.\(value)")
        case .height(let value): .init("pili.height.\(value)")
        }
    }
    var order: CGFloat {
        switch self { case .medium: 0.5; case .large: 1; case .fraction(let value): value; case .height(let value): value / 1000 }
    }
    @MainActor var native: UISheetPresentationController.Detent {
        switch self {
        case .medium: .medium()
        case .large: .large()
        case .fraction(let value): .custom(identifier: identifier) { max(1, min($0.maximumDetentValue, $0.maximumDetentValue * value)) }
        case .height(let value): .custom(identifier: identifier) { max(1, min($0.maximumDetentValue, value)) }
        }
    }
}

/// Forwards ChunUI's dirty-state delegate, while preventing dismissal during a
/// write. A busy sheet must never offer a misleading Save/Discard escape route.
@MainActor
final class PiliSheetOwner: NSObject, UISheetPresentationControllerDelegate {
    weak var host: UIViewController?
    private weak var original: (any UIAdaptivePresentationControllerDelegate)?
    private var locks = Set<UUID>()
    private var detents: [PiliSheetDetent] = []
    private var selection: Binding<PiliSheetDetent>?

    func attach(_ host: UIViewController) {
        self.host = host
        original = host.presentationController?.delegate
        host.presentationController?.delegate = self
        applyLocks()
        applyDetents()
    }
    func setLock(_ id: UUID, disabled: Bool) {
        if disabled { locks.insert(id) } else { locks.remove(id) }
        applyLocks()
    }
    private func applyLocks() {
        guard let host, let presentation = host.presentationController else { return }
        host.isModalInPresentation = !locks.isEmpty || original?.presentationControllerShouldDismiss?(presentation) == false
    }
    func setDetents(_ values: Set<PiliSheetDetent>, selection: Binding<PiliSheetDetent>?) {
        detents = values.sorted { $0.order < $1.order }
        self.selection = selection
        applyDetents()
    }
    private func applyDetents() {
        guard !detents.isEmpty, let sheet = host?.sheetPresentationController else { return }
        sheet.animateChanges {
            sheet.detents = detents.map { value in
                let detent = value.native
                // New detents must retain the material installed on the host.
                detent.backgroundEffect = UIGlassEffect(style: .regular)
                return detent
            }
            sheet.selectedDetentIdentifier = (selection?.wrappedValue ?? detents[0]).identifier
        }
    }
    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        locks.isEmpty && (original?.presentationControllerShouldDismiss?(presentationController) ?? true)
    }
    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        if locks.isEmpty { original?.presentationControllerDidAttemptToDismiss?(presentationController) }
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        original?.presentationControllerDidDismiss?(presentationController)
    }
    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {
        if let value = detents.first(where: { $0.identifier == sheetPresentationController.selectedDetentIdentifier }) {
            selection?.wrappedValue = value
        }
    }
}

private struct PiliSheetInteraction: ViewModifier {
    let disabled: Bool
    @Environment(\.piliSheetOwner) private var owner
    @State private var id = UUID()
    func body(content: Content) -> some View {
        content
            .onChange(of: disabled, initial: true) { _, value in owner?.setLock(id, disabled: value) }
            .onDisappear { owner?.setLock(id, disabled: false) }
    }
}

private struct PiliSheetSizing: ViewModifier {
    let detents: Set<PiliSheetDetent>
    let selection: Binding<PiliSheetDetent>?
    @Environment(\.piliSheetOwner) private var owner
    func body(content: Content) -> some View {
        content
            .onChange(of: detents, initial: true) { _, _ in update() }
            .onChange(of: selection?.wrappedValue) { _, _ in update() }
    }
    private func update() { owner?.setDetents(detents, selection: selection) }
}

extension View {
    func piliInteractiveDismissDisabled(_ disabled: Bool) -> some View { modifier(PiliSheetInteraction(disabled: disabled)) }
    func piliPresentationDetents(_ detents: Set<PiliSheetDetent>, selection: Binding<PiliSheetDetent>? = nil) -> some View {
        modifier(PiliSheetSizing(detents: detents, selection: selection))
    }
}
