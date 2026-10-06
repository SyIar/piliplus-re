import ChunUI
import SwiftUI
import UIKit

private struct PiliSheetCloseKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

private struct PiliSheetOwnerKey: EnvironmentKey {
    static let defaultValue: PiliSheetOwner? = nil
}

extension EnvironmentValues {
    var piliSheetClose: (@MainActor () -> Void)? {
        get { self[PiliSheetCloseKey.self] }
        set { self[PiliSheetCloseKey.self] = newValue }
    }
    var piliSheetOwner: PiliSheetOwner? {
        get { self[PiliSheetOwnerKey.self] }
        set { self[PiliSheetOwnerKey.self] = newValue }
    }
}

/// Dismisses the owning ChunUI sheet, with SwiftUI navigation as the fallback.
@propertyWrapper
struct PiliDismiss: DynamicProperty {
    @Environment(\.dismiss) private var native
    @Environment(\.piliSheetClose) private var close
    var wrappedValue: @MainActor () -> Void { { if let close { close() } else { native() } } }
}

@MainActor
enum PiliPresentation {
    static weak var dependencies: AppDependencies?

    static func present<Content: View>(_ config: CCSheetConfig = .form,
        onDismiss: (() -> Void)? = nil, onPresent: ((UIViewController) -> Void)? = nil,
        @ViewBuilder content: () -> Content) {
        let root = content()
        let owner = PiliSheetOwner()
        var glassConfig = config
        // Request transparency before the hosting hierarchy is created; clearing
        // an already opaque hosting root leaves a solid safe-area seam.
        glassConfig.frostedGlass = true
        if !config.frostedGlass {
            let detents: Set<PiliSheetDetent> = switch config.detent {
            case .large: [.large]
            case .medium: [.medium]
            case .mediumAndLarge: [.medium, .large]
            case .compact(let height): [.height(height)]
            }
            owner.setDetents(detents, selection: nil)
        }
        AppHelper.shared.presentSheet(glassConfig, onDismiss: onDismiss, onPresent: { host in
            owner.attach(host)
            onPresent?(host)
        }) {
            PiliPresentationRoot(content: root)
                .environment(\.piliSheetClose, { owner.host?.dismiss(animated: true) })
                .environment(\.piliSheetOwner, owner)
        }
    }

    /// Keep ChunUI's detents, keyboard handling and dirty-state controller.
    /// The system owns one glass backdrop, including accessibility adaptation.
    static func configureSheet(_ host: UIViewController) {
        host.loadViewIfNeeded()
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        // ChunUI pins its hosting view to the keyboard guide. With the default
        // true value, a hidden keyboard still leaves a home-indicator-height
        // strip, cutting the content off before the sheet's bottom corners.
        // False reaches the physical bottom when hidden and still tracks the
        // real keyboard when shown, without ignoring SwiftUI safe areas.
        host.view.keyboardLayoutGuide.usesBottomSafeArea = false
        for child in host.children {
            child.view.backgroundColor = .clear
            child.view.isOpaque = false
        }
        if let sheet = host.sheetPresentationController {
            sheet.backgroundEffect = UIGlassEffect(style: .regular)
            for detent in sheet.detents { detent.backgroundEffect = UIGlassEffect(style: .regular) }
        }
    }
}

struct PiliPresentationRoot<Content: View>: View {
    let content: Content
    var isSheet = true
    var body: some View {
        Group {
            if let dependencies = PiliPresentation.dependencies {
                PiliConnectedPresentationRoot(content: content, dependencies: dependencies, library: dependencies.libraryStore)
            } else { content }
        }
        .environment(\.piliPresentedPage, isSheet)
        .modifier(PiliAppChrome())
    }
}

private struct PiliConnectedPresentationRoot<Content: View>: View {
    let content: Content
    let dependencies: AppDependencies
    @ObservedObject var library: LibraryStore
    var body: some View {
        content
            .environmentObject(dependencies)
            .environmentObject(dependencies.sessionStore)
            .environmentObject(library)
            .environmentObject(dependencies.homeRecommendDiagnosticsStore)
            .environment(\.appThemeTintColor, library.appTintColor)
            .tint(library.appTintColor)
            .preferredColorScheme(library.appearanceMode.preferredColorScheme)
    }
}

/// Binding adapter only: presentation and interaction remain owned by ChunUI.
@MainActor
final class PiliSheetSession: ObservableObject {
    private weak var host: UIViewController?
    private var activeID: AnyHashable?
    private var token: UUID?
    private var desiredID: AnyHashable?
    private var makeContent: (() -> AnyView)?
    private var didClose: (() -> Void)?
    private var config = CCSheetConfig.form

    func synchronize(id: AnyHashable?, config: CCSheetConfig, content: @escaping () -> AnyView,
                     onClose: @escaping () -> Void) {
        desiredID = id
        makeContent = content
        didClose = onClose
        self.config = config
        reconcile()
    }

    func close() {
        desiredID = nil
        reconcile()
    }

    private func reconcile() {
        if token != nil {
            if activeID != desiredID { host?.dismiss(animated: true) }
            return
        }
        guard let id = desiredID, let makeContent else {
            // Release source view/binding captures after the presentation ends.
            self.makeContent = nil
            didClose = nil
            return
        }
        let current = UUID()
        token = current
        activeID = id
        let onClose = didClose
        PiliPresentation.present(config, onDismiss: { [self] in
            guard token == current else { return }
            token = nil; activeID = nil; host = nil
            if desiredID == id { desiredID = nil }
            onClose?()
            reconcile()
        }, onPresent: { [self] controller in
            host = controller
            if desiredID != id { controller.dismiss(animated: true) }
        }) {
            makeContent().environment(\.piliSheetClose, { [self] in close() })
        }
    }
}

private struct PiliBoundSheet<Item: Identifiable, Sheet: View>: ViewModifier where Item.ID: Sendable {
    @Binding var item: Item?
    let config: CCSheetConfig
    let onDismiss: (() -> Void)?
    let sheet: (Item) -> Sheet
    @Environment(\.self) private var environment
    @StateObject private var session = PiliSheetSession()

    func body(content: Content) -> some View {
        content
            .onChange(of: item?.id, initial: true) { _, _ in synchronize() }
    }
    private func synchronize() {
        let value = item
        let id = value?.id
        let inherited = environment
        session.synchronize(id: id.map(AnyHashable.init), config: config, content: {
            AnyView(PiliInheritedSheetContent(environment: inherited, close: { session.close() }) {
                if let value { sheet(value) }
            })
        }, onClose: {
            // A newer route must survive dismissal of the previous controller.
            if item?.id == id { item = nil }
            onDismiss?()
        })
    }
}

private struct PiliInheritedSheetContent<Content: View>: View {
    let environment: EnvironmentValues
    let close: @MainActor () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.piliSheetOwner) private var owner
    var body: some View {
        content()
            // Forward app routing and comment context, never the parent's
            // system traits or CCEditSheetContext into a newly presented host.
            .environment(\.openURL, environment.openURL)
            .environment(\.openAppURLAction, environment.openAppURLAction)
            .environment(\.openVideoAction, environment.openVideoAction)
            .environment(\.openLiveRoomAction, environment.openLiveRoomAction)
            .environment(\.prewarmVideoRouteAction, environment.prewarmVideoRouteAction)
            .environment(\.openPgcSeasonRouteAction, environment.openPgcSeasonRouteAction)
            .environment(\.openVideoOwnerRouteAction, environment.openVideoOwnerRouteAction)
            .environment(\.showsVideoCoverDurationBadges, environment.showsVideoCoverDurationBadges)
            .environment(\.playerNativeControlMetrics, environment.playerNativeControlMetrics)
            .environment(\.videoCommentReplyComposerAction, environment.videoCommentReplyComposerAction)
            .environment(\.piliVideoTools, environment.piliVideoTools)
            .environment(\.commentLikeTarget, environment.commentLikeTarget)
            .environment(\.commentContentOwnerMID, environment.commentContentOwnerMID)
            .environment(\.markRelatedVideoNavigation, environment.markRelatedVideoNavigation)
            .environment(\.commentSheetToolbarConfiguration, environment.commentSheetToolbarConfiguration)
            .environment(\.dynamicDetailNavigationPath, environment.dynamicDetailNavigationPath)
            .environment(\.preloadedOriginalDynamicDetails, environment.preloadedOriginalDynamicDetails)
            .environment(\.dynamicCommentHitAreaVisualizationEnabled, environment.dynamicCommentHitAreaVisualizationEnabled)
            .environment(\.piliPresentedPage, true)
            .environment(\.piliSheetOwner, owner)
            .environment(\.piliSheetClose, close)
    }
}

private struct PiliBooleanSheetItem: Identifiable { let id = true }

extension View {
    func piliSheet<Item: Identifiable, Content: View>(item: Binding<Item?>,
        config: CCSheetConfig = .form, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content) -> some View where Item.ID: Sendable {
        modifier(PiliBoundSheet(item: item, config: config, onDismiss: onDismiss, sheet: content))
    }

    func piliSheet<Content: View>(isPresented: Binding<Bool>, config: CCSheetConfig = .form,
        onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        piliSheet(item: Binding<PiliBooleanSheetItem?>(
            get: { isPresented.wrappedValue ? PiliBooleanSheetItem() : nil },
            set: { isPresented.wrappedValue = $0 != nil }), config: config, onDismiss: onDismiss) { _ in content() }
    }
}
