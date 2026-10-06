import ChunUI
import SwiftUI

struct HomeFeedNavigationChrome: ViewModifier {
    @Environment(\.rootNavigationTitleHidden) private var rootNavigationTitleHidden
    @EnvironmentObject private var sessionStore: SessionStore
    @ObservedObject var viewModel: HomeViewModel
    let modeActions: HomeFeedModeActions
    let scrollActions: HomeFeedScrollActions
    let nativeRefreshActionStore: HomeNativeRefreshActionStore
    let accountMessageViewModel: AccountMessageCenterViewModel?
    let isDetailPresented: Bool
    let onOpenAccountMessages: () -> Void

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HomeFeedModeMenu(currentMode: viewModel.mode, onSelectMode: switchMode)
                        .opacity(navigationChromeOpacity)
                        .disabled(hidesNavigationChrome)
                        .accessibilityHidden(hidesNavigationChrome)
                        .animation(.smooth(duration: 0.18), value: hidesNavigationChrome)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    GlassEffectContainer(spacing: 10) {
                        HStack(spacing: 10) {
                            HStack(spacing: 0) {
                                Button {
                                    AppHelper.shared.presentSheet(.sheet) { PiliDLNAView() }
                                } label: {
                                    Image(systemName: "tv").frame(width: 42, height: 42)
                                }
                                .accessibilityLabel("投屏设备")
                                accountMessageButton.frame(width: 42, height: 42)
                            }
                            .buttonStyle(.plain)
                            .piliLiquidGlass(in: Capsule(), interactive: true)

                            NavigationLink(value: MineOverlayRoute.multiAccountSettings) {
                                AvatarRemoteImage(urlString: sessionStore.user?.face, pixelSize: 88) {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.system(size: 32, weight: .regular))
                                        .foregroundStyle(.primary)
                                }
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("账号管理")
                        }
                    }
                    .opacity(navigationChromeOpacity)
                    .disabled(hidesNavigationChrome)
                    .accessibilityHidden(hidesNavigationChrome)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .nativeTopNavigationChrome()
            .task(id: PiliAccountIdentity(viewModel.pageCoordinator.api.requestSnapshot())) {
                await PiliBlacklistedCreators.shared.refresh(api: viewModel.pageCoordinator.api)
            }
            .onReceive(PiliBlacklistedCreators.shared.$ids) { ids in
                guard UserDefaults.standard.object(forKey: "piliplus.filter.blacklistedCreators") as? Bool ?? true else { return }
                let kept = viewModel.videos.filter { !ids.contains($0.owner?.mid ?? 0) }
                if kept.count != viewModel.videos.count {
                    // @Published sends before storage changes; use the incoming snapshot.
                    viewModel.updateFeed(viewModel.videos, lastSeenMarkerIndex: viewModel.lastSeenMarkerIndex,
                                         blockedUserIDs: ids)
                }
            }
    }

    private var hidesNavigationChrome: Bool {
        isDetailPresented || rootNavigationTitleHidden.wrappedValue
    }

    private var navigationChromeOpacity: Double {
        hidesNavigationChrome ? 0 : 1
    }

    @ViewBuilder
    private var accountMessageButton: some View {
        if let accountMessageViewModel {
            HomeAccountMessageButton(
                viewModel: accountMessageViewModel,
                action: onOpenAccountMessages
            )
        } else {
            HomeAccountMessageButtonContent(
                hasUnread: false,
                action: onOpenAccountMessages
            )
        }
    }

    private func switchMode(_ mode: HomeFeedMode) {
        modeActions.switchMode(
            mode,
            viewModel: viewModel,
            scrollActions: scrollActions,
            nativeRefreshActionStore: nativeRefreshActionStore
        )
    }
}

extension View {
    func homeFeedNavigationChrome(
        viewModel: HomeViewModel,
        modeActions: HomeFeedModeActions,
        scrollActions: HomeFeedScrollActions,
        nativeRefreshActionStore: HomeNativeRefreshActionStore,
        accountMessageViewModel: AccountMessageCenterViewModel?,
        isDetailPresented: Bool = false,
        onOpenAccountMessages: @escaping () -> Void
    ) -> some View {
        modifier(
            HomeFeedNavigationChrome(
                viewModel: viewModel,
                modeActions: modeActions,
                scrollActions: scrollActions,
                nativeRefreshActionStore: nativeRefreshActionStore,
                accountMessageViewModel: accountMessageViewModel,
                isDetailPresented: isDetailPresented,
                onOpenAccountMessages: onOpenAccountMessages
            )
        )
    }
}

private struct HomeAccountMessageButton: View {
    @ObservedObject var viewModel: AccountMessageCenterViewModel
    let action: () -> Void

    var body: some View {
        HomeAccountMessageButtonContent(
            hasUnread: viewModel.hasUnreadMessages,
            action: action
        )
    }
}

private struct HomeAccountMessageButtonContent: View {
    @Environment(\.appThemeTintColor) private var appTintColor
    let hasUnread: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "bell")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.primary)
                .overlay(alignment: .topTrailing) {
                    if hasUnread {
                        Circle().fill(.red).frame(width: 7, height: 7).offset(x: 4, y: -2)
                    }
                }
        }
        .accessibilityLabel("账号消息")
        .accessibilityValue(hasUnread ? "有未读消息" : "全部已读")
    }
}
