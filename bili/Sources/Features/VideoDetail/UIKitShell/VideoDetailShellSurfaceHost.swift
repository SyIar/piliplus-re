import ChunUI
import AVFoundation
import Combine
import SwiftUI
import PiliPlaybackCore
import UIKit

/// UIKit detail host with an independent SwiftUI controls overlay.
///
/// UIKit owns the frame; SwiftUI renders VideoSurfaceView directly.
/// Controls, gestures and loading indicators remain separate overlays.
/// Rotation does not replace the entire BiliPlayerView presentation.
@MainActor
final class VideoDetailShellSurfaceHost: UIView {
    @MainActor
    final class State: ObservableObject {
        @Published var isBareSurfaceTransitionActive = false
        @Published var retainsChromeDuringBareSurfaceTransition = false
        @Published var isCollapsedChromeActive = false
        @Published var playbackControlsHideRequestGeneration = 0
        @Published var playerViewModel: PlayerStateViewModel
        @Published var videoAspectRatio: CGFloat = 16.0 / 9.0

        init(playerViewModel: PlayerStateViewModel) {
            self.playerViewModel = playerViewModel
        }

        func setBareSurfaceTransitionActive(_ active: Bool, retainsChromeTree: Bool) {
            if active {
                // Retain the controls before entering the bare-surface state.
                retainsChromeDuringBareSurfaceTransition = retainsChromeTree
                isBareSurfaceTransitionActive = true
            } else {
                // Exit the bare state before releasing the retained controls.
                isBareSurfaceTransitionActive = false
                retainsChromeDuringBareSurfaceTransition = false
            }
        }

        func requestPlaybackControlsHideForRotation() {
            playbackControlsHideRequestGeneration &+= 1
        }
    }

    private let state: State
    private let overlayState: VideoDetailShellOverlayState
    private let experimentState: VideoDetailPerformanceExperimentState
    private let libraryStore: LibraryStore
    private let rotationCoordinator: PlaybackRotationCoordinator
    private let surfaceHostView: any VideoDetailPlayerSurfaceHostingView
    private let overlayHostingController: UIHostingController<PlayerOverlayHostRoot>
    private var cancellables = Set<AnyCancellable>()
    private var rotationChromePrewarmGeneration = 0
    private var isRotationChromePrewarming = false
    private(set) var isRotationChromePrewarmed = false
    private(set) var isTornDown = false

    init(
        playerViewModel: PlayerStateViewModel,
        detailViewModel: VideoDetailViewModel,
        dependencies: AppDependencies,
        runtimeSettings: VideoDetailRuntimeSettingsStore,
        rotationCoordinator: PlaybackRotationCoordinator,
        onShowMoreControls: @escaping (@escaping () -> Void) -> Void,
        onDismissMoreControls: @escaping () -> Void,
        onRequestFullscreen: @escaping () -> Void,
        onExitFullscreen: @escaping () -> Void,
        onToggleDanmaku: @escaping () -> Void,
        onShowDanmakuSettings: @escaping () -> Void,
        onNavigateBack: @escaping () -> Void
    ) {
        let state = State(playerViewModel: playerViewModel)
        let experimentState = VideoDetailPerformanceExperimentState(
            directUIKitSurfaceEnabled: true,
            narrowPlayerOverlayObservationEnabled: true
        )
        let overlayState = VideoDetailShellOverlayState(
            detailViewModel: detailViewModel,
            experimentState: experimentState
        )
        self.state = state
        self.overlayState = overlayState
        self.experimentState = experimentState
        self.libraryStore = dependencies.libraryStore
        self.rotationCoordinator = rotationCoordinator
        self.surfaceHostView = VideoDetailSwiftUISurfaceHostingView(
            viewModel: playerViewModel,
            isPictureInPictureEnabled: dependencies.libraryStore.pictureInPictureEnabled
                && !playerViewModel.isAudioOnlyPlayback
        )
        let overlayRoot = PlayerOverlayHostRoot(
            detailViewModel: detailViewModel,
            state: state,
            rotationCoordinator: rotationCoordinator,
            overlayState: overlayState,
            experimentState: experimentState,
            runtimeSettings: runtimeSettings,
            usesNarrowObservation: true,
            dependencies: dependencies,
            onShowMoreControls: onShowMoreControls,
            onDismissMoreControls: onDismissMoreControls,
            onRequestFullscreen: onRequestFullscreen,
            onExitFullscreen: onExitFullscreen,
            onToggleDanmaku: onToggleDanmaku,
            onShowDanmakuSettings: onShowDanmakuSettings,
            onNavigateBack: onNavigateBack
        )
        self.overlayHostingController = UIHostingController(rootView: overlayRoot)
        super.init(frame: .zero)

        backgroundColor = .black
        overlayHostingController.view.backgroundColor = .clear
        overlayHostingController.view.isOpaque = false
        overlayHostingController.view.isUserInteractionEnabled = true
        if #available(iOS 16.4, *) {
            overlayHostingController.safeAreaRegions = []
        }
        let hostedSurfaceView = surfaceHostView.hostedView
        hostedSurfaceView.translatesAutoresizingMaskIntoConstraints = false
        hostedSurfaceView.isUserInteractionEnabled = false
        overlayHostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostedSurfaceView)
        addSubview(overlayHostingController.view)
        NSLayoutConstraint.activate([
            hostedSurfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostedSurfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostedSurfaceView.topAnchor.constraint(equalTo: topAnchor),
            hostedSurfaceView.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlayHostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayHostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayHostingController.view.topAnchor.constraint(equalTo: topAnchor),
            overlayHostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        dependencies.libraryStore.$pictureInPictureEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.surfaceHostView.setPictureInPictureEnabled(
                        isEnabled && !self.state.playerViewModel.isAudioOnlyPlayback
                    )
                }
            }
            .store(in: &cancellables)

    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(to parent: UIViewController) {
        guard !isTornDown else { return }
        surfaceHostView.attach(to: parent)
        guard overlayHostingController.parent == nil else { return }
        parent.addChild(overlayHostingController)
        overlayHostingController.didMove(toParent: parent)
    }

    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        cancelRotationChromePrewarm()
        cancellables.removeAll()
        surfaceHostView.tearDown()
        surfaceHostView.hostedView.removeFromSuperview()
        overlayHostingController.willMove(toParent: nil)
        overlayHostingController.view.removeFromSuperview()
        overlayHostingController.removeFromParent()
    }

    func requestPlaybackControlsHideForRotation() {
        state.requestPlaybackControlsHideForRotation()
    }

    func markRotationChromePrewarmed() {
        isRotationChromePrewarmed = true
    }

    /// Keep danmaku mounted while the system rotates the bare video surface.
    /// Retain hidden controls to avoid rebuilding every overlay after rotation.
    func setBareSurfaceTransitionActive(_ active: Bool, retainsChromeTree: Bool = false) {
        guard state.isBareSurfaceTransitionActive != active
            || state.retainsChromeDuringBareSurfaceTransition != retainsChromeTree
        else { return }
        cancelRotationChromePrewarm()
        overlayState.setBareSurfaceTransitionActive(active)
        experimentState.setBareSurfaceTransitionActive(active)
        state.setBareSurfaceTransitionActive(active, retainsChromeTree: retainsChromeTree)
        UIView.performWithoutAnimation {
            overlayHostingController.view.isHidden = false
            overlayHostingController.view.isUserInteractionEnabled = !active
            surfaceHostView.hostedView.isUserInteractionEnabled = false
        }
    }

    func refreshLayoutImmediately() {
        UIView.performWithoutAnimation {
            setNeedsLayout()
            layoutIfNeeded()
            surfaceHostView.refreshLayoutImmediately()
            if !state.isBareSurfaceTransitionActive {
                overlayHostingController.view.setNeedsLayout()
                overlayHostingController.view.layoutIfNeeded()
            }
        }
    }

    func prewarmRotationChrome() {
        guard !isRotationChromePrewarming,
              !state.isBareSurfaceTransitionActive
        else { return }
        isRotationChromePrewarmed = false
        isRotationChromePrewarming = true
        rotationChromePrewarmGeneration &+= 1
        let generation = rotationChromePrewarmGeneration
        let prewarmLandscape = !rotationCoordinator.isLandscape

        UIView.performWithoutAnimation {
            state.setBareSurfaceTransitionActive(true, retainsChromeTree: true)
            rotationCoordinator.beginChromePrewarm(for: prewarmLandscape)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.isRotationChromePrewarming,
                  self.rotationChromePrewarmGeneration == generation
            else { return }
            self.layoutRotationChromePrewarm()
            UIView.performWithoutAnimation {
                self.rotationCoordinator.endChromePrewarm()
            }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.isRotationChromePrewarming,
                      self.rotationChromePrewarmGeneration == generation
                else { return }
                self.layoutRotationChromePrewarm()
                UIView.performWithoutAnimation {
                    self.state.setBareSurfaceTransitionActive(false, retainsChromeTree: true)
                }
                self.isRotationChromePrewarming = false
                self.isRotationChromePrewarmed = true
            }
        }
    }

    func cancelRotationChromePrewarm() {
        guard isRotationChromePrewarming else { return }
        rotationChromePrewarmGeneration &+= 1
        isRotationChromePrewarming = false
        UIView.performWithoutAnimation {
            rotationCoordinator.endChromePrewarm()
            state.setBareSurfaceTransitionActive(false, retainsChromeTree: true)
        }
    }

    /// Rebind the overlay in place when quality changes replace the player.
    func setPlayerViewModel(_ playerViewModel: PlayerStateViewModel) {
        guard state.playerViewModel !== playerViewModel else { return }
        state.playerViewModel = playerViewModel
        surfaceHostView.setPlayerViewModel(playerViewModel)
        surfaceHostView.setPictureInPictureEnabled(
            libraryStore.pictureInPictureEnabled
                && !playerViewModel.isAudioOnlyPlayback
        )
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        surfaceHostView.setVideoGravity(gravity)
    }

    func setVideoAspectRatio(_ aspectRatio: CGFloat) {
        guard aspectRatio > 0.1, abs(state.videoAspectRatio - aspectRatio) > 0.001 else { return }
        state.videoAspectRatio = aspectRatio
    }

    func setCollapsedChromeActive(_ active: Bool) {
        guard state.isCollapsedChromeActive != active else { return }
        state.isCollapsedChromeActive = active
    }

    private func layoutRotationChromePrewarm() {
        overlayHostingController.view.setNeedsLayout()
        overlayHostingController.view.layoutIfNeeded()
    }

}

extension VideoDetailShellSurfaceHost: PlayerSurfaceHosting {
    var surfaceView: UIView { self }

    func setLandscape(_: Bool) {}

    func setPortraitFullscreen(_: Bool) {}
}

private struct VideoDetailShellOverlaySnapshot: Equatable {
    var historyVideo: VideoItem
    var recordsPlaybackHistory = true
    var historyCID: Int?
    var historyDuration: TimeInterval?
    var isDanmakuEnabled = true
    var isSwitchingPlayQuality = false
    var playbackContentMode: PlayerPlaybackContentMode = .video
    var isSwitchingVideoListenMode = false

    init(
        detail: VideoItem,
        recordsPlaybackHistory: Bool,
        selectedCID: Int?,
        isDanmakuEnabled: Bool,
        isSwitchingPlayQuality: Bool,
        playbackContentMode: PlayerPlaybackContentMode,
        isSwitchingVideoListenMode: Bool
    ) {
        self.historyVideo = detail
        self.recordsPlaybackHistory = recordsPlaybackHistory
        self.historyCID = recordsPlaybackHistory ? (selectedCID ?? detail.cid) : nil
        self.historyDuration = detail.duration.map(TimeInterval.init)
        self.isDanmakuEnabled = isDanmakuEnabled
        self.isSwitchingPlayQuality = isSwitchingPlayQuality
        self.playbackContentMode = playbackContentMode
        self.isSwitchingVideoListenMode = isSwitchingVideoListenMode
    }
}

@MainActor
private final class VideoDetailShellOverlayState: ObservableObject {
    @Published private(set) var snapshot: VideoDetailShellOverlaySnapshot
    private var isBareSurfaceTransitionActive = false
    private var pendingSnapshot: VideoDetailShellOverlaySnapshot?
    private weak var experimentState: VideoDetailPerformanceExperimentState?
    private var cancellables = Set<AnyCancellable>()

    init(
        detailViewModel: VideoDetailViewModel,
        experimentState: VideoDetailPerformanceExperimentState
    ) {
        self.experimentState = experimentState
        self.snapshot = VideoDetailShellOverlaySnapshot(
            detail: detailViewModel.detail,
            recordsPlaybackHistory: detailViewModel.playbackOptions.recordsPlaybackHistory,
            selectedCID: detailViewModel.selectedCID,
            isDanmakuEnabled: detailViewModel.isDanmakuEnabled,
            isSwitchingPlayQuality: detailViewModel.isSwitchingPlayQuality,
            playbackContentMode: detailViewModel.playbackContentMode,
            isSwitchingVideoListenMode: detailViewModel.isSwitchingVideoListenMode
        )

        let playbackSnapshotPublisher = Publishers.CombineLatest4(
            detailViewModel.$detail,
            detailViewModel.$selectedCID,
            detailViewModel.$isDanmakuEnabled,
            detailViewModel.$isSwitchingPlayQuality
        )
        let listenModePublisher = detailViewModel.$playbackContentMode
            .combineLatest(detailViewModel.$isSwitchingVideoListenMode)

        Publishers.CombineLatest(playbackSnapshotPublisher, listenModePublisher)
        .map { playback, listenMode in
            let (detail, selectedCID, isDanmakuEnabled, isSwitchingPlayQuality) = playback
            let (playbackContentMode, isSwitchingVideoListenMode) = listenMode
            return VideoDetailShellOverlaySnapshot(
                detail: detail,
                recordsPlaybackHistory: detailViewModel.playbackOptions.recordsPlaybackHistory,
                selectedCID: selectedCID,
                isDanmakuEnabled: isDanmakuEnabled,
                isSwitchingPlayQuality: isSwitchingPlayQuality,
                playbackContentMode: playbackContentMode,
                isSwitchingVideoListenMode: isSwitchingVideoListenMode
            )
        }
        .removeDuplicates()
        .sink { [weak self] snapshot in
            self?.receive(snapshot)
        }
        .store(in: &cancellables)
    }

    func setBareSurfaceTransitionActive(_ active: Bool) {
        guard isBareSurfaceTransitionActive != active else { return }
        isBareSurfaceTransitionActive = active
        if !active {
            flushPendingSnapshot()
        }
    }

    private func receive(_ nextSnapshot: VideoDetailShellOverlaySnapshot) {
        guard nextSnapshot != snapshot else { return }
        if isBareSurfaceTransitionActive {
            pendingSnapshot = nextSnapshot
            experimentState?.recordOverlayDeferred()
            return
        }
        snapshot = nextSnapshot
        experimentState?.recordOverlayPublish()
    }

    private func flushPendingSnapshot() {
        guard let pendingSnapshot else { return }
        self.pendingSnapshot = nil
        guard pendingSnapshot != snapshot else { return }
        snapshot = pendingSnapshot
        experimentState?.recordOverlayFlush()
    }
}

private extension UIView {
    func removeLayerAnimationsRecursively() {
        layer.removeAllAnimations()
        subviews.forEach { $0.removeLayerAnimationsRecursively() }
    }
}

@MainActor
private final class VideoDetailPlayerOverlayLegacyObservationBridge: ObservableObject {
    @Published private(set) var revision = 0

    private var updateScheduled = false
    private var cancellables = Set<AnyCancellable>()

    init(
        viewModel: PlayerStateViewModel,
        libraryStore: LibraryStore,
        isEnabled: Bool
    ) {
        guard isEnabled else { return }
        Publishers.Merge(
            viewModel.objectWillChange,
            libraryStore.objectWillChange
        )
        .sink { [weak self] in
            self?.scheduleUpdate()
        }
        .store(in: &cancellables)
    }

    private func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            self.revision &+= 1
        }
    }
}

private struct PlayerOverlayHostRoot: View {
    let detailViewModel: VideoDetailViewModel
    @ObservedObject var state: VideoDetailShellSurfaceHost.State
    @ObservedObject var rotationCoordinator: PlaybackRotationCoordinator
    @ObservedObject var overlayState: VideoDetailShellOverlayState
    let experimentState: VideoDetailPerformanceExperimentState
    let runtimeSettings: VideoDetailRuntimeSettingsStore
    let usesNarrowObservation: Bool
    let dependencies: AppDependencies
    let onShowMoreControls: (@escaping () -> Void) -> Void
    let onDismissMoreControls: () -> Void
    let onRequestFullscreen: () -> Void
    let onExitFullscreen: () -> Void
    let onToggleDanmaku: () -> Void
    let onShowDanmakuSettings: () -> Void
    let onNavigateBack: () -> Void

    var body: some View {
        let overlaySnapshot = overlayState.snapshot
        let overlay = SurfaceOnlyPlayerOverlayRoot(
            viewModel: state.playerViewModel,
            detailViewModel: detailViewModel,
            rotationCoordinator: rotationCoordinator,
            overlaySnapshot: overlaySnapshot,
            experimentState: experimentState,
            runtimeSettings: runtimeSettings,
            usesNarrowObservation: usesNarrowObservation,
            dependencies: dependencies,
            isBareSurfaceTransitionActive: state.isBareSurfaceTransitionActive,
            retainsChromeDuringBareSurfaceTransition: state.retainsChromeDuringBareSurfaceTransition,
            isCollapsedChromeActive: state.isCollapsedChromeActive,
            playbackControlsHideRequestGeneration: state.playbackControlsHideRequestGeneration,
            videoAspectRatio: state.videoAspectRatio,
            onShowMoreControls: onShowMoreControls,
            onDismissMoreControls: onDismissMoreControls,
            onToggleDanmaku: onToggleDanmaku,
            onShowDanmakuSettings: onShowDanmakuSettings,
            onNavigateBack: onNavigateBack,
            onRequestFullscreen: onRequestFullscreen,
            onExitFullscreen: onExitFullscreen
        )

        Group {
            if usesNarrowObservation {
                overlay
            } else {
                overlay.id(ObjectIdentifier(state.playerViewModel))
            }
        }
        .ignoresSafeArea()
    }
}

private struct SurfaceOnlyPlayerOverlayRoot: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let viewModel: PlayerStateViewModel
    let detailViewModel: VideoDetailViewModel
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore

    let overlaySnapshot: VideoDetailShellOverlaySnapshot
    let experimentState: VideoDetailPerformanceExperimentState
    let usesNarrowObservation: Bool
    let dependencies: AppDependencies
    @ObservedObject var rotationCoordinator: PlaybackRotationCoordinator
    let isBareSurfaceTransitionActive: Bool
    let retainsChromeDuringBareSurfaceTransition: Bool
    let isCollapsedChromeActive: Bool
    let playbackControlsHideRequestGeneration: Int
    let videoAspectRatio: CGFloat
    let onShowMoreControls: (@escaping () -> Void) -> Void
    let onDismissMoreControls: () -> Void
    let onToggleDanmaku: () -> Void
    let onShowDanmakuSettings: () -> Void
    let onNavigateBack: () -> Void
    let onRequestFullscreen: () -> Void
    let onExitFullscreen: () -> Void

    @StateObject private var surfaceState: PlayerSurfaceStateModel
    @StateObject private var playbackControlsVisibility = PlayerPlaybackControlsVisibilityModel()
    @StateObject private var rotationTransitionSnapshotModel = PlayerRotationTransitionSnapshotModel()
    @StateObject private var seekTransitionSnapshotModel = PlayerRotationTransitionSnapshotModel()
    @StateObject private var appBackgroundRecoverySnapshotModel = PlayerRotationTransitionSnapshotModel()
    @StateObject private var speedBoostModel = PlayerSpeedBoostModel()
    @StateObject private var seekPreviewModel = PlayerSeekPreviewModel()
    @StateObject private var playbackProgressCoordinator = PlayerPlaybackProgressCoordinator()
    @StateObject private var progressReporter = PlayerPlaybackProgressReporter()
    @StateObject private var legacyObservationBridge: VideoDetailPlayerOverlayLegacyObservationBridge
    @State private var lastPreparedScrubProgress = -1.0
    @State private var isMoreControlsPresented = false
    @State private var portraitMoreControlsRequestID: UUID?
    @State private var isMoreControlsButtonPressed = false
    @State private var isVideoListenQueuePresented = false
    @State private var isGlassControlsLocked = false
    @State private var isGlassMenuPresented = false
    @AppStorage("piliplus.player.lockOrientation") private var locksOrientation = true

    private var isLandscape: Bool {
        rotationCoordinator.chromeLandscape
    }

    private var isPortraitFullscreen: Bool {
        rotationCoordinator.isPortraitFullscreen
    }

    init(
        viewModel: PlayerStateViewModel,
        detailViewModel: VideoDetailViewModel,
        rotationCoordinator: PlaybackRotationCoordinator,
        overlaySnapshot: VideoDetailShellOverlaySnapshot,
        experimentState: VideoDetailPerformanceExperimentState,
        runtimeSettings: VideoDetailRuntimeSettingsStore,
        usesNarrowObservation: Bool,
        dependencies: AppDependencies,
        isBareSurfaceTransitionActive: Bool,
        retainsChromeDuringBareSurfaceTransition: Bool,
        isCollapsedChromeActive: Bool,
        playbackControlsHideRequestGeneration: Int,
        videoAspectRatio: CGFloat,
        onShowMoreControls: @escaping (@escaping () -> Void) -> Void,
        onDismissMoreControls: @escaping () -> Void,
        onToggleDanmaku: @escaping () -> Void,
        onShowDanmakuSettings: @escaping () -> Void,
        onNavigateBack: @escaping () -> Void,
        onRequestFullscreen: @escaping () -> Void,
        onExitFullscreen: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.detailViewModel = detailViewModel
        self.rotationCoordinator = rotationCoordinator
        self.overlaySnapshot = overlaySnapshot
        self.experimentState = experimentState
        self.runtimeSettings = runtimeSettings
        self.usesNarrowObservation = usesNarrowObservation
        self.dependencies = dependencies
        _libraryStore = ObservedObject(wrappedValue: dependencies.libraryStore)
        self.isBareSurfaceTransitionActive = isBareSurfaceTransitionActive
        self.retainsChromeDuringBareSurfaceTransition = retainsChromeDuringBareSurfaceTransition
        self.isCollapsedChromeActive = isCollapsedChromeActive
        self.playbackControlsHideRequestGeneration = playbackControlsHideRequestGeneration
        self.videoAspectRatio = videoAspectRatio
        self.onShowMoreControls = onShowMoreControls
        self.onDismissMoreControls = onDismissMoreControls
        self.onToggleDanmaku = onToggleDanmaku
        self.onShowDanmakuSettings = onShowDanmakuSettings
        self.onNavigateBack = onNavigateBack
        self.onRequestFullscreen = onRequestFullscreen
        self.onExitFullscreen = onExitFullscreen
        _surfaceState = StateObject(wrappedValue: PlayerSurfaceStateModel(viewModel: viewModel))
        _legacyObservationBridge = StateObject(
            wrappedValue: VideoDetailPlayerOverlayLegacyObservationBridge(
                viewModel: viewModel,
                libraryStore: dependencies.libraryStore,
                isEnabled: !usesNarrowObservation
            )
        )
    }

    @State private var didAutoEnterFullscreen = false

    var body: some View {
        let _ = legacyObservationBridge.revision
        let context = runtimeContext
        let renderContext = context.renderContext
        let renderState = BiliPlayerViewRenderState(
            context: renderContext,
            verticalSizeClass: verticalSizeClass
        )
        let visibilityActions = renderState.visibilityActions
        let speedActions = renderState.speedBoostActions
        let nativeActions = BiliPlayerNativeControlsActionBuilder(
            viewModel: viewModel,
            configuration: renderContext.configuration,
            visibilityActions: visibilityActions,
            seekPreviewModel: renderContext.seekPreviewModel,
            seekPreviewAPI: renderContext.seekPreviewAPI,
            seekPreviewContext: renderContext.seekPreviewContext,
            holdCurrentFrameForSeek: holdCurrentFrameForSeek,
            prepareUserSeekWarmup: prepareUserSeekWarmupIfNeeded,
            resetPreparedScrubProgress: { lastPreparedScrubProgress = -1 },
            isFullscreenActiveOverride: isPortraitFullscreen ? true : nil
        ).actions
        let shouldKeepChromeMounted = keepsChromeMounted && !isCollapsedChromeActive

        GeometryReader { proxy in
            let videoInsets = visibleVideoInsets(in: proxy.size)
            let chromeState = surfaceChromeState(
                context: renderContext,
                renderState: renderState,
                contentInsets: videoInsets
            )
            ZStack {
                if isAudioOnlyPlayback {
                    VideoListenArtworkLayer(
                        video: overlaySnapshot.historyVideo,
                        isLandscape: isLandscape
                    )
                    .allowsHitTesting(false)
                    .zIndex(0.5)
                }

                if shouldKeepChromeMounted {
                    Group {
                        BiliPlayerSurfaceGestureLayerHost(
                            content: Color.clear
                                .frame(maxWidth: .infinity, maxHeight: .infinity),
                            visibilityActions: visibilityActions,
                            speedBoostActions: speedActions,
                            viewModel: viewModel,
                            allowsDoubleTapPlaybackToggle: true,
                            seekPreviewModel: renderContext.seekPreviewModel,
                            seekPreviewAPI: renderContext.seekPreviewAPI,
                            seekPreviewContext: renderContext.seekPreviewContext,
                            holdCurrentFrameForSeek: holdCurrentFrameForSeek,
                            prepareUserSeekWarmup: prepareUserSeekWarmupIfNeeded,
                            resetPreparedScrubProgress: { lastPreparedScrubProgress = -1 },
                            isFullscreen: configuration.isFullscreenActive,
                            onSwipeFullscreen: isAudioOnlyPlayback ? nil : (configuration.isFullscreenActive ? onExitFullscreen : onRequestFullscreen)
                        )
                        .allowsHitTesting(!isGlassControlsLocked)
                        .zIndex(1)

                        BiliPlayerSurfaceOverlayLayer(
                            state: chromeState,
                            speedBoostModel: renderContext.speedBoostModel,
                            seekPreviewModel: renderContext.seekPreviewModel
                        )
                            .zIndex(2)

                        if isLandscape && !isAudioOnlyPlayback {
                            if chromeState.showsActivePlaybackControls || isGlassControlsLocked {
                                glassFullscreenControls(playback: nativeActions, visibility: visibilityActions)
                                    .opacity(isGlassControlsLocked ? 1 : chromeState.playbackControlsOpacity)
                                    .allowsHitTesting(isGlassControlsLocked || chromeState.playbackControlsAllowsHitTesting)
                                    .zIndex(3)
                            }
                        } else {
                        BiliPlayerControlsOverlayLayer(
                            state: chromeState,
                            playbackControls: AnyView(
                                BiliPlayerNativeControlsHost(
                                    context: renderContext,
                                    renderState: renderState,
                                    actions: nativeActions,
                                    progressStyle: .telegram,
                                    isFullscreenActiveOverride: isPortraitFullscreen ? true : nil
                                )
                            ),
                            usesFullscreenSafeArea: isPortraitFullscreen
                        )
                        .zIndex(3)

                        }

                        if isAudioOnlyPlayback {
                            persistentMoreControlsButton(contentInsets: videoInsets)
                        }

                        if runtimeSettings.playerPerformanceOverlayEnabled {
                            performanceOverlay(contentInsets: videoInsets, in: proxy.size)
                                .zIndex(8)
                        }

                        let rotationReportMetricsID = overlaySnapshot.historyVideo.bvid
                        if runtimeSettings.videoRotationFrameReportOverlayEnabled,
                           !rotationReportMetricsID.isEmpty {
                            VideoRotationFrameReportFloatingWindow(
                                metricsID: rotationReportMetricsID,
                                contentInsets: videoInsets
                            )
                            .zIndex(8.5)
                        }

                        if isLandscape, isMoreControlsPresented {
                            SurfaceOnlyLandscapeMoreControlsOverlay(
                                detailViewModel: detailViewModel,
                                viewModel: viewModel,
                                libraryStore: libraryStore,
                                qualityStore: detailViewModel.playbackRenderStore.qualityControlStore,
                                selectPlayVariant: { detailViewModel.selectPlayVariant($0) },
                                onToggleDanmaku: onToggleDanmaku,
                                contentInsets: videoInsets,
                                close: { isMoreControlsPresented = false }
                            )
                            .transition(.opacity)
                            .zIndex(9)
                        }
                    }
                    .opacity(isBareSurfaceTransitionActive ? 0 : 1)
                    .allowsHitTesting(!isBareSurfaceTransitionActive)
                }

                if showsCenterPlaybackControl {
                    PiliInteractivePlaybackControlGate(controller: detailViewModel.piliInteractive) {
                        centerPlaybackControl
                    }
                    .zIndex(5)
                }

                if !isAudioOnlyPlayback {
                    VideoDetailPlayerSurfaceDanmakuLayer(
                        store: detailViewModel.danmakuRenderStore,
                        playerViewModel: viewModel,
                        usesLandscapePlaybackChrome: configuration.isFullscreenActive,
                        isLayoutTransitioning: isBareSurfaceTransitionActive,
                        onPlaybackTime: { detailViewModel.updateDanmakuPlaybackTime($0, underLoad: $1) }
                    )
                    .allowsHitTesting(!isBareSurfaceTransitionActive)
                    .zIndex(2.5)
                    PiliOnlineSubtitleLayer(controller: detailViewModel.piliSubtitles, api: detailViewModel.api,
                                            video: detailViewModel.detail, cid: detailViewModel.selectedCID,
                                            clock: viewModel.playbackClock, landscape: configuration.isFullscreenActive)
                        .zIndex(2.6)
                    PiliSponsorManualPrompt(player: viewModel).zIndex(2.7)
                    PiliVideoToolsOverlay(model: detailViewModel, store: detailViewModel.piliVideoTools, clock: viewModel.playbackClock)
                        .zIndex(2.7)
                    PiliInteractiveOverlay(controller: detailViewModel.piliInteractive, viewModel: detailViewModel)
                        .zIndex(3.5)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .background {
            PlaybackDetailPlayerReadinessProbe(
                playerViewModel: viewModel,
                context: .video(overlaySnapshot.historyVideo)
            )
        }
        .environmentObject(dependencies)
        .environmentObject(libraryStore)
        .piliVideoAspect(player: viewModel)
        .environment(\.piliVideoTools, detailViewModel.piliVideoTools)
        .environment(\.piliPlaybackIsMuted, viewModel.isMuted || viewModel.sponsorBlockMutesAudio || viewModel.volume <= 0)
        .environment(\.appThemeTintColor, runtimeSettings.appTintColor)
        .biliPlayerLifecycle(
            isFullscreenActive: configuration.isFullscreenActive,
            presentation: configuration.presentation,
            isLayoutTransitioning: configuration.isLayoutTransitioning,
            isSecondaryControlsPresented: configuration.isSecondaryControlsPresented,
            isPictureInPictureEnabled: effectivePictureInPictureEnabled,
            actions: context.lifecycleActions
        )
        .onAppear {
            if !isAudioOnlyPlayback {
                detailViewModel.scheduleDanmakuLoadIfNeeded()
            }
        }
        .onReceive(viewModel.$hasPresentedPlayback.removeDuplicates()) { shown in
            guard shown, !didAutoEnterFullscreen else { return }
            didAutoEnterFullscreen = true
            if UserDefaults.standard.bool(forKey: "piliplus.player.autoFullscreen"), !isAudioOnlyPlayback,
               !configuration.isFullscreenActive, !isBareSurfaceTransitionActive {
                Task { @MainActor in await Task.yield(); if !detailViewModel.isPlaybackInvalidatedForNavigation { onRequestFullscreen() } }
            }
        }
        .onChange(of: ObjectIdentifier(viewModel)) { _, _ in
            guard usesNarrowObservation else { return }
            context.lifecycleActions.onPlayerChanged()
            experimentState.recordPlayerRebind()
        }
        .onChange(of: isLandscape) { _, isLandscape in
            // Prewarming can briefly toggle this state during a bare transition.
            // It must not dismiss a newly presented portrait menu.
            guard !isBareSurfaceTransitionActive else { return }
            if isLandscape {
                portraitMoreControlsRequestID = nil
                onDismissMoreControls()
                isVideoListenQueuePresented = false
            } else {
                isMoreControlsPresented = false
                isGlassMenuPresented = false
            }
        }
        .onChange(of: overlaySnapshot.playbackContentMode) { _, mode in
            if mode != .audioOnly {
                isVideoListenQueuePresented = false
            }
            guard mode == .audioOnly else { return }
            isMoreControlsPresented = false
            isGlassMenuPresented = false
            portraitMoreControlsRequestID = nil
            onDismissMoreControls()
            if isLandscape {
                onExitFullscreen()
            }
        }
        .onChange(of: isBareSurfaceTransitionActive) { _, isActive in
            guard isActive else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isMoreControlsPresented = false
                isVideoListenQueuePresented = false
                isGlassMenuPresented = false
            }
            playbackControlsVisibility.cancelAutoHide()
        }
        .onChange(of: isLandscape) { _, landscape in
            if !landscape { isGlassControlsLocked = false }
        }
        .onChange(of: isGlassControlsLocked) { _, locked in
            rotationCoordinator.setControlsLocked(locked, locksOrientation: locksOrientation)
        }
        .onChange(of: locksOrientation) { _, enabled in
            rotationCoordinator.setControlsLocked(isGlassControlsLocked, locksOrientation: enabled)
        }
        .onChange(of: playbackControlsHideRequestGeneration) { _, _ in
            playbackControlsVisibility.hide(animated: false)
        }
        .onChange(of: surfaceState.isUserSeeking) { _, isUserSeeking in
            updateSeekTransitionSnapshot(isUserSeeking: isUserSeeking)
        }
        .onReceive(surfaceState.$snapshot.dropFirst()) { _ in
            guard usesNarrowObservation else { return }
            experimentState.recordPlayerStatePublish()
        }
        .onReceive(runtimeSettings.$snapshot.dropFirst()) { _ in
            guard usesNarrowObservation else { return }
            experimentState.recordSettingsStatePublish()
        }
        .piliSheet(isPresented: $isVideoListenQueuePresented) {
            NavigationStack {
                SurfaceOnlyVideoListenQueuePage(
                    detailViewModel: detailViewModel,
                    closeSheet: { isVideoListenQueuePresented = false }
                )
            }
            .piliPresentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func glassFullscreenControls(
        playback: PlayerNativePlaybackControlsActions,
        visibility: BiliPlayerPlaybackControlsVisibilityActions
    ) -> some View {
        PiliGlassFullscreenControls(
            title: overlaySnapshot.historyVideo.title,
            author: overlaySnapshot.historyVideo.owner?.name ?? "",
            shareURL: URL(string: "https://www.bilibili.com/video/\(overlaySnapshot.historyVideo.bvid)"),
            clock: viewModel.playbackClock,
            isPlaying: surfaceState.isPlaying,
            canSeek: surfaceState.canSeek,
            hasPrevious: viewModel.canRequestPreviousTrack,
            hasNext: viewModel.canRequestNextTrack,
            isDanmakuEnabled: overlaySnapshot.isDanmakuEnabled,
            isLocked: $isGlassControlsLocked,
            playback: playback,
            actions: PiliGlassFullscreenActions(
                close: handleBackButton,
                cast: {
                    visibility.markInteraction()
                    PiliPresentation.present(.sheet) { PiliDLNAView(source: { try .online(detailViewModel) }) }
                },
                settings: {
                    visibility.markInteraction(keepsVisible: true)
                    isMoreControlsPresented = true
                },
                subtitles: {
                    visibility.markInteraction()
                    PiliSubtitleSettingsView.present(controller: detailViewModel.piliSubtitles) { seconds in viewModel.seek(by: seconds - viewModel.currentTime) }
                },
                danmaku: { visibility.markInteraction(); onShowDanmakuSettings() },
                queue: { visibility.markInteraction(keepsVisible: true); isVideoListenQueuePresented = true },
                previous: { visibility.markInteraction(); viewModel.requestPreviousTrack() },
                next: { visibility.markInteraction(); viewModel.requestNextTrack() },
                skip: { seconds in
                    guard surfaceState.canSeek, !viewModel.isTerminated else { return }
                    visibility.markInteraction()
                    holdCurrentFrameForSeek()
                    viewModel.seek(by: seconds)
                },
                interaction: { visibility.markInteraction() },
                rateChanged: { rate in viewModel.setPlaybackRate(rate) },
                capture: { PiliMediaCaptureView.present(detailViewModel) },
                menuPresentationChanged: { presented in
                    isGlassMenuPresented = presented
                    visibility.markInteraction(keepsVisible: presented)
                }
            ),
            interactionAccessory: AnyView(PiliFullscreenVideoReactions(
                viewModel: detailViewModel, store: detailViewModel.interactionRenderStore,
                markInteraction: { visibility.markInteraction() }
            )),
            playbackRate: viewModel.playbackRate
        )
    }

    private var backButton: some View {
        VideoDetailPlayerSurfaceBackButtonHost(action: handleBackButton)
            .environment(\.playerNativeControlMetrics, controlMetrics)
            .accessibilityIdentifier("ui.player.back")
    }

    private func handleBackButton() {
        if fullscreenMode != nil || isPortraitFullscreen {
            onExitFullscreen()
        } else {
            onNavigateBack()
        }
    }

    private var fullscreenMode: PlayerFullscreenMode? {
        guard !isAudioOnlyPlayback else { return nil }
        return isLandscape ? .landscape(.landscapeRight) : nil
    }

    private var isAudioOnlyPlayback: Bool {
        overlaySnapshot.playbackContentMode == .audioOnly
    }

    private var effectivePictureInPictureEnabled: Bool {
        runtimeSettings.pictureInPictureEnabled && !isAudioOnlyPlayback
    }

    private var keepsChromeMounted: Bool {
        !isBareSurfaceTransitionActive || retainsChromeDuringBareSurfaceTransition
    }

    private var showsCenterPlaybackControl: Bool {
        keepsChromeMounted
            && !isCollapsedChromeActive
            && !isBareSurfaceTransitionActive
            && !(isLandscape && !isAudioOnlyPlayback)
            && surfaceState.showsExplicitPlaybackStartControl
            && surfaceState.errorMessage == nil
    }

    private var centerPlaybackControl: some View {
        PlayerNativeGlassIconButton(
            systemName: "play.fill",
            accessibilityLabel: "\u{64ad}\u{653e}",
            metrics: centerPlaybackControlMetrics
        ) {
            viewModel.play()
            playbackControlsVisibility.showAndSchedule(
                showsPlaybackControls: keepsChromeMounted,
                isLayoutTransitioning: isBareSurfaceTransitionActive
            )
        }
        .biliLiquidGlassForeground(shadowOpacity: 0.20)
    }

    private var centerPlaybackControlMetrics: PlayerNativeControlMetrics {
        controlMetrics.sized(controlHeight: 56, iconSize: 24)
    }

    private var configuration: BiliPlayerViewConfiguration {
        BiliPlayerViewOptions(
            presentation: isLandscape ? .fullScreen : .embedded,
            showsNavigationChrome: false,
            showsPlaybackControls: keepsChromeMounted,
            showsStartupLoadingIndicator: keepsChromeMounted && viewModel.wantsAutoplay,
            pausesOnDisappear: false,
            controlsAccessory: isAudioOnlyPlayback
                ? AnyView(videoListenQuickControls)
                : AnyView(PlayerInlineQuickControls(player: viewModel, subtitles: showSubtitles)),
            topLeadingControlsAccessory: keepsChromeMounted ? AnyView(backButton) : nil,
            isDanmakuEnabled: keepsChromeMounted && overlaySnapshot.isDanmakuEnabled && !isAudioOnlyPlayback,
            onToggleDanmaku: isAudioOnlyPlayback ? nil : onToggleDanmaku,
            onShowDanmakuSettings: isAudioOnlyPlayback ? nil : onShowDanmakuSettings,
            isSecondaryControlsPresented: keepsChromeMounted
                && (isMoreControlsPresented
                    || portraitMoreControlsRequestID != nil
                    || isVideoListenQueuePresented
                    || isGlassMenuPresented
                    || isGlassControlsLocked),
            ignoresContainerSafeArea: true,
            keepsPlayerSurfaceStable: true,
            fullscreenMode: fullscreenMode,
            isLayoutTransitioning: isBareSurfaceTransitionActive,
            usesLiveSurfaceDuringLayoutTransition: true,
            disablesSurfaceImplicitLayoutAnimations: true,
            showsRotationTransitionSnapshot: false,
            onRequestFullscreen: isAudioOnlyPlayback ? nil : onRequestFullscreen,
            onExitFullscreen: isAudioOnlyPlayback ? nil : onExitFullscreen
        ).configuration()
    }

    private var videoListenQuickControls: some View {
        SurfaceOnlyVideoListenQuickControls(
            detailViewModel: detailViewModel,
            libraryStore: libraryStore,
            metrics: controlMetrics,
            showQueue: { isVideoListenQueuePresented = true }
        )
    }

    private var runtimeContext: BiliPlayerViewRuntimeContext {
        BiliPlayerViewRuntimeContextBuilder(
            dependencies: dependencies,
            libraryStore: libraryStore,
            viewModel: viewModel,
            surfaceState: surfaceState,
            playbackControlsVisibility: playbackControlsVisibility,
            rotationTransitionSnapshotModel: rotationTransitionSnapshotModel,
            seekTransitionSnapshotModel: seekTransitionSnapshotModel,
            appBackgroundRecoverySnapshotModel: appBackgroundRecoverySnapshotModel,
            speedBoostModel: speedBoostModel,
            seekPreviewModel: seekPreviewModel,
            playbackProgressCoordinator: playbackProgressCoordinator,
            progressReporter: progressReporter,
            historyVideo: overlaySnapshot.recordsPlaybackHistory ? overlaySnapshot.historyVideo : nil,
            historyCID: overlaySnapshot.historyCID,
            historyDuration: overlaySnapshot.historyDuration,
            configuration: configuration,
            isPictureInPictureEnabled: effectivePictureInPictureEnabled,
            videoGravity: .resizeAspect,
            holdCurrentFrameForSeek: holdCurrentFrameForSeek,
            prepareUserSeekWarmup: prepareUserSeekWarmupIfNeeded,
            resetPreparedScrubProgress: { lastPreparedScrubProgress = -1 }
        ).context
    }

    private var moreControlsButton: some View {
        SurfaceOnlyUIKitMoreControlsButton(
            metrics: controlMetrics,
            systemImageName: "ellipsis",
            usesGlass: isAudioOnlyPlayback,
            onPressBegan: {
                isMoreControlsButtonPressed = true
                playbackControlsVisibility.cancelAutoHide()
            },
            onPressEnded: {
                isMoreControlsButtonPressed = false
                guard portraitMoreControlsRequestID == nil,
                      !isMoreControlsPresented
                else { return }
                playbackControlsVisibility.scheduleAutoHide(
                    showsPlaybackControls: keepsChromeMounted,
                    isLayoutTransitioning: isBareSurfaceTransitionActive
                )
            }
        ) {
            playbackControlsVisibility.cancelAutoHide()
            if isLandscape {
                withAnimation(.default) {
                    isMoreControlsPresented = true
                }
            } else {
                let requestID = UUID()
                portraitMoreControlsRequestID = requestID
                onShowMoreControls {
                    guard portraitMoreControlsRequestID == requestID else { return }
                    portraitMoreControlsRequestID = nil
                }
            }
        }
        .frame(width: controlMetrics.controlHeight, height: controlMetrics.controlHeight)
        .frame(width: 44, height: controlMetrics.controlHeight, alignment: .trailing)
        .biliPlayerExpandedHitTarget(horizontal: 0, vertical: 8)
        .accessibilityLabel("\u{66f4}\u{591a}\u{64ad}\u{653e}\u{8bbe}\u{7f6e}")
    }

    private func showSubtitles() {
        playbackControlsVisibility.cancelAutoHide()
        PiliSubtitleSettingsView.present(controller: detailViewModel.piliSubtitles) { seconds in
            viewModel.seek(by: seconds - viewModel.currentTime)
        }
    }

    private var inlineTopControls: some View {
        HStack(spacing: 0) {
            PiliGlassPlayerButton(symbol: "airplayvideo", title: "\u{6295}\u{5c4f}", grouped: true) {
                PiliPresentation.present(.sheet) { PiliDLNAView(source: { try .online(detailViewModel) }) }
            }
            PiliGlassPlayerButton(symbol: "text.bubble", title: "\u{5f39}\u{5e55}\u{8bbe}\u{7f6e}", grouped: true,
                                  action: onShowDanmakuSettings)
            moreControlsButton
        }
        .piliLiquidGlass(in: Capsule(), overVideo: true)
    }

    private func persistentMoreControlsButton(contentInsets: EdgeInsets) -> some View {
        GeometryReader { _ in
            let safeAreaInsets = fullscreenSafeAreaInsets()
            let topInset = max(safeAreaInsets.top, contentInsets.top)
            let trailingInset = max(safeAreaInsets.right, contentInsets.trailing)
            VStack {
                HStack {
                    Spacer()
                    moreControlsButton
                        .padding(.top, topControlsPadding + topInset)
                        .padding(.trailing, moreControlsTrailingPadding(trailingInset: trailingInset))
                }
                Spacer()
            }
        }
        .opacity(isMoreControlsButtonPressed ? 1 : playbackControlsVisibility.opacity)
        .allowsHitTesting(
            isMoreControlsButtonPressed || playbackControlsVisibility.acceptsHitTesting
        )
        .zIndex(4)
    }

    private func performanceOverlay(contentInsets: EdgeInsets, in size: CGSize) -> some View {
        let safeAreaInsets = fullscreenSafeAreaInsets()
        let topInset = max(safeAreaInsets.top, contentInsets.top)
        let leadingInset = max(safeAreaInsets.left, contentInsets.leading)
        let trailingInset = max(safeAreaInsets.right, contentInsets.trailing)
        let bottomInset = max(safeAreaInsets.bottom, contentInsets.bottom)
        let horizontalPadding = horizontalControlsPadding
        let availableWidth = max(1, size.width - leadingInset - trailingInset - horizontalPadding * 2)
        let availableHeight = max(1, size.height - topInset - bottomInset - topControlsPadding - 14)
        let panelWidth = min(isLandscape ? 340 : 320, max(260, availableWidth))
        let maximumHeight = min(isLandscape ? 420 : 360, max(180, availableHeight))

        return VStack {
            HStack {
                VideoDetailPerformanceOverlayContainer(
                    store: detailViewModel.networkDiagnosticsRenderStore,
                    experimentState: experimentState,
                    panelWidth: panelWidth,
                    maximumHeight: maximumHeight
                )
                .padding(.top, topControlsPadding + topInset)
                .padding(.leading, horizontalPadding + leadingInset)

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func visibleVideoInsets(in size: CGSize) -> EdgeInsets {
        guard configuration.isFullscreenActive,
              size.width > 1,
              size.height > 1,
              videoAspectRatio > 0.1
        else { return EdgeInsets() }

        let containerAspect = size.width / size.height
        let horizontalInset: CGFloat
        let verticalInset: CGFloat
        if videoAspectRatio > containerAspect {
            let fittedHeight = size.width / videoAspectRatio
            horizontalInset = 0
            verticalInset = max(0, (size.height - fittedHeight) / 2)
        } else {
            let fittedWidth = size.height * videoAspectRatio
            horizontalInset = max(0, (size.width - fittedWidth) / 2)
            verticalInset = 0
        }

        return EdgeInsets(
            top: verticalInset,
            leading: horizontalInset,
            bottom: verticalInset,
            trailing: horizontalInset
        )
    }

    private func moreControlsTrailingPadding(trailingInset: CGFloat) -> CGFloat {
        horizontalControlsPadding + trailingInset
    }

    private var usesFullscreenChromeSpacing: Bool {
        configuration.presentation == .fullScreen || configuration.isFullscreenActive
    }

    private var topControlsPadding: CGFloat {
        usesFullscreenChromeSpacing ? 14 : 10
    }

    private var horizontalControlsPadding: CGFloat {
        usesFullscreenChromeSpacing ? 14 : 10
    }

    private func fullscreenSafeAreaInsets() -> UIEdgeInsets {
        guard configuration.isFullscreenActive,
              let window = UIApplication.shared.playbackDetailForegroundKeyWindow
        else { return .zero }
        return window.safeAreaInsets
    }

    private var controlMetrics: PlayerNativeControlMetrics {
        if fullscreenMode?.isLandscape == true || verticalSizeClass == .compact {
            return .landscape
        }
        return .portrait
    }

    private var usesFullscreenStatusChrome: Bool {
        !isAudioOnlyPlayback
    }

    private var showsFullscreenStatusControls: Bool {
        VideoDetailSurfaceChromePolicy.showsFullscreenStatusControls(
            usesFullscreenChrome: usesFullscreenStatusChrome
                && fullscreenMode?.isLandscape == true,
            isPortraitFullscreen: isPortraitFullscreen
        )
    }

    private func surfaceChromeState(
        context: BiliPlayerViewRenderContext,
        renderState: BiliPlayerViewRenderState,
        contentInsets: EdgeInsets
    ) -> BiliPlayerSurfaceChromeState {
        return BiliPlayerSurfaceChromeState(
            presentation: context.configuration.presentation,
            surfaceOverlay: context.configuration.surfaceOverlay,
            rotationSnapshot: nil,
            seekSnapshot: seekTransitionSnapshotModel.snapshot,
            appBackgroundRecoverySnapshot: appBackgroundRecoverySnapshotModel.snapshot,
            rotationFallbackCoverURL: nil,
            rotationSnapshotOpacity: 0,
            seekSnapshotOpacity: seekTransitionSnapshotModel.opacity,
            appBackgroundRecoverySnapshotOpacity: appBackgroundRecoverySnapshotModel.opacity,
            constrainsRotationSnapshotToVideoAspect: false,
            showsPlayerLoadingChrome: renderState.showsPlayerLoadingChrome
                && !overlaySnapshot.isSwitchingPlayQuality,
            isBuffering: context.surfaceState.isBuffering,
            isPlaying: context.surfaceState.isPlaying,
            hasPresentedPlayback: context.surfaceState.hasPresentedPlayback,
            showsInlineLoadingProgress: renderState.showsInlineLoadingProgress,
            isUserSeeking: context.surfaceState.isUserSeeking,
            showsActivePlaybackControls: renderState.showsActivePlaybackControls,
            playbackControlsOpacity: playbackControlsVisibility.opacity,
            playbackControlsAllowsHitTesting: playbackControlsVisibility.acceptsHitTesting,
            topLeadingControlsAccessory: context.configuration.topLeadingControlsAccessory,
            topCenterControlsAccessory: showsFullscreenStatusControls
                ? AnyView(VideoDetailFullscreenClockControl())
                : nil,
            topTrailingControlsAccessory: !isLandscape && !isAudioOnlyPlayback
                ? AnyView(inlineTopControls)
                : (showsFullscreenStatusControls ? AnyView(VideoDetailFullscreenBatteryControl()) : nil),
            isFullscreenActive: context.configuration.isFullscreenActive,
            controlsBottomLift: context.configuration.controlsBottomLift,
            controlsHorizontalInset: context.configuration.controlsHorizontalInset,
            contentInsets: contentInsets,
            errorMessage: context.surfaceState.errorMessage
        )
    }

    private func prepareUserSeekWarmupIfNeeded(_ progress: Double, force: Bool = false) {
        let clampedProgress = min(max(progress, 0), 1)
        guard force || abs(clampedProgress - lastPreparedScrubProgress) >= 0.008 else { return }
        lastPreparedScrubProgress = clampedProgress
        configuration.onPrepareForUserSeek?(clampedProgress)
    }

    private func holdCurrentFrameForSeek() {
        seekTransitionSnapshotModel.hold(
            hasPresentedPlayback: surfaceState.hasPresentedPlayback,
            surfaceLayoutGeneration: viewModel.surfaceLayoutGeneration
        ) {
            viewModel.makePlaybackTransitionSnapshot()
        }
    }

    private func updateSeekTransitionSnapshot(isUserSeeking: Bool) {
        if isUserSeeking {
            guard viewModel.shouldHoldSeekSnapshotAtInteractionStart else { return }
            holdCurrentFrameForSeek()
        } else {
            seekTransitionSnapshotModel.releaseForSeekTransition(
                isReadyForReveal: {
                    viewModel.isSeekRecoverySnapshotReadyForReveal()
                },
                onReleased: {
                    viewModel.finishUserSeekVisualReveal()
                }
            )
        }
    }
}

struct SurfaceOnlyMoreControlsSheet: View {
    @PiliDismiss private var dismiss
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var viewModel: PlayerStateViewModel
    @ObservedObject var qualityStore: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let closeAction: (() -> Void)?

    init(
        detailViewModel: VideoDetailViewModel,
        viewModel: PlayerStateViewModel,
        qualityStore: VideoDetailQualityControlRenderStore,
        selectPlayVariant: @escaping (PlayVariant) -> Void,
        onToggleDanmaku: @escaping () -> Void,
        close: (() -> Void)? = nil
    ) {
        self.detailViewModel = detailViewModel
        self.viewModel = viewModel
        self.qualityStore = qualityStore
        self.selectPlayVariant = selectPlayVariant
        self.onToggleDanmaku = onToggleDanmaku
        self.closeAction = close
    }

    var body: some View {
        SurfaceOnlyMoreControlsNavigationContent(
            detailViewModel: detailViewModel,
            viewModel: viewModel,
            libraryStore: detailViewModel.libraryStore,
            qualityStore: qualityStore,
            selectPlayVariant: selectPlayVariant,
            onToggleDanmaku: onToggleDanmaku,
            close: closeSheet
        )
        .piliPresentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func closeSheet() {
        if let closeAction {
            closeAction()
        } else {
            dismiss()
        }
    }
}

private struct SurfaceOnlyVideoListenQuickControls: View {
    @ObservedObject private var piliPlaybackPreferences = PiliPlaybackPreferences.shared
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var libraryStore: LibraryStore
    let metrics: PlayerNativeControlMetrics
    let showQueue: () -> Void

    var body: some View {
        HStack(spacing: metrics.controlSpacing) {
            PlayerNativeGlassIconButton(
                systemName: "list.bullet",
                accessibilityLabel: "\u{64ad}\u{653e}\u{5217}\u{8868}，\(detailViewModel.videoListenQueueAccessoryTitle)",
                metrics: metrics,
                action: showQueue
            )

            Menu {
                ForEach(PlaybackOrder.allCases, id: \.rawValue) { order in
                    Button {
                        piliPlaybackPreferences.setOrder(order)
                    } label: {
                        PiliLabel(
                            order.title,
                            systemImage: piliPlaybackPreferences.order == order
                                ? "checkmark"
                                : order.systemImage
                        )
                    }
                }
            } label: {
                PiliIcon(systemName: piliPlaybackPreferences.order.systemImage, size: iconSize)
                    .font(.system(size: iconSize, weight: .semibold))
                    .frame(width: metrics.controlHeight, height: metrics.controlHeight)
            }
            .biliPlayerCompactGlassCircle(metrics: metrics)
            .accessibilityLabel("\u{64ad}\u{653e}\u{987a}\u{5e8f}，\(piliPlaybackPreferences.order.title)")

            Menu {
                ForEach(VideoListenSleepTimerOption.allCases) { option in
                    Button {
                        detailViewModel.setVideoListenSleepTimer(option)
                    } label: {
                        PiliLabel(
                            option.title,
                            systemImage: detailViewModel.isPiliSleepTimerOptionSelected(option)
                                ? "checkmark"
                                : option.systemImage
                        )
                    }
                }
            } label: {
                sleepTimerLabel
            }
            .biliPlayerCompactGlassCapsule(metrics: metrics)
            .accessibilityLabel("\u{5b9a}\u{65f6}\u{5173}\u{95ed}，\(detailViewModel.videoListenSleepTimerAccessoryTitle)")
        }
    }

    @ViewBuilder
    private var sleepTimerLabel: some View {
        if let deadline = detailViewModel.videoListenSleepTimerDeadline {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(VideoListenSleepTimerCountdownFormatter.text(deadline: deadline, now: context.date))
                    .piliFont(.sm).monospacedDigit().fontWeight(.semibold)
                    .lineLimit(1)
                    .frame(width: max(48, metrics.controlHeight + 20), height: metrics.controlHeight)
            }
        } else {
            PiliIcon(systemName: detailViewModel.videoListenSleepTimerOption.systemImage, size: iconSize)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: metrics.controlHeight, height: metrics.controlHeight)
        }
    }

    private var iconSize: CGFloat {
        metrics.iconSize
    }
}

private struct VideoListenArtworkLayer: View {
    let video: VideoItem
    let isLandscape: Bool

    private let artworkAspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                backgroundArtwork
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                Color.black.opacity(0.52)

                if proxy.size.height < 280 {
                    compactContent(in: proxy.size)
                } else {
                    regularContent(in: proxy.size)
                }
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\u{542c}\u{89c6}\u{9891}\u{4e2d}，\(video.title)，\(ownerName)")
    }

    private var backgroundArtwork: some View {
        CachedRemoteImage(
            url: artworkURL,
            targetPixelSize: 1_280,
            animatesAppearance: false
        ) { image in
            image
                .resizable()
                .scaledToFill()
                .scaleEffect(1.12)
                .blur(radius: 24)
        } placeholder: {
            Color.black
        }
    }

    private func compactContent(in size: CGSize) -> some View {
        let horizontalPadding = min(20.0, max(size.width * 0.05, 12.0))
        let spacing = min(14.0, max(size.width * 0.035, 10.0))
        let availableWidth = max(size.width - horizontalPadding * 2 - spacing, 0)
        let artworkMaximumWidth = min(148.0, availableWidth * 0.43)
        let artworkMaximumHeight = max(size.height - 28, 0)
        let artworkSize = fittedArtworkSize(
            maximumWidth: artworkMaximumWidth,
            maximumHeight: artworkMaximumHeight
        )
        let metadataWidth = max(availableWidth - artworkSize.width, 0)

        return HStack(spacing: spacing) {
            foregroundArtwork
                .frame(width: artworkSize.width, height: artworkSize.height)

            metadata(alignment: .leading, textAlignment: .leading, titleLines: 2)
                .frame(width: metadataWidth, alignment: .leading)
                .layoutPriority(1)
        }
        .padding(.horizontal, horizontalPadding)
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func regularContent(in size: CGSize) -> some View {
        let artworkSize = fittedArtworkSize(
            maximumWidth: min(isLandscape ? 300 : 220, size.width * 0.52),
            maximumHeight: max(size.height * 0.55, 0)
        )

        return VStack(spacing: isLandscape ? 14 : 12) {
            foregroundArtwork
                .frame(width: artworkSize.width, height: artworkSize.height)

            metadata(alignment: .center, textAlignment: .center, titleLines: 2)
                .frame(maxWidth: min(460, size.width * 0.70))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var foregroundArtwork: some View {
        CachedRemoteImage(
            url: artworkURL,
            targetPixelSize: 960,
            animatesAppearance: true
        ) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            BiliMediaPlaceholder(style: .video, iconSize: 22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.34), radius: 12, x: 0, y: 7)
    }

    private func metadata(
        alignment: HorizontalAlignment,
        textAlignment: TextAlignment,
        titleLines: Int
    ) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            PiliLabel("\u{542c}\u{89c6}\u{9891}\u{4e2d}", systemImage: "headphones")
                .piliFont(.sm).fontWeight(.semibold)
                .foregroundStyle(.white)

            Text(video.title)
                .piliFont(.baseBold)
                .foregroundStyle(.white)
                .multilineTextAlignment(textAlignment)
                .lineLimit(titleLines)

            Text(ownerName)
                .piliFont(.base)
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(1)
        }
    }

    private var ownerName: String {
        let name = video.owner?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "\u{672a}\u{77e5} UP \u{4e3b}" : name
    }

    private var artworkURL: URL? {
        guard let picture = video.pic?.normalizedBiliURL(), !picture.isEmpty else { return nil }
        return URL(string: picture.biliCoverThumbnailURL(width: 1_280, height: 720))
    }

    private func fittedArtworkSize(
        maximumWidth: CGFloat,
        maximumHeight: CGFloat
    ) -> CGSize {
        guard maximumWidth > 0, maximumHeight > 0 else { return .zero }
        let widthFromHeight = maximumHeight * artworkAspectRatio
        let width = min(maximumWidth, widthFromHeight)
        return CGSize(width: width, height: width / artworkAspectRatio)
    }
}

private struct SurfaceOnlyMoreControlsNavigationContent: View {
    @ObservedObject private var piliPlaybackPreferences = PiliPlaybackPreferences.shared
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var viewModel: PlayerStateViewModel
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var qualityStore: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let close: () -> Void

    var body: some View {
        NavigationStack {
            PiliList {
                NavigationLink { PiliAudioLanguageView(viewModel: detailViewModel) } label: { PiliLabel("\u{539f}\u{58f0}\u{7ffb}\u{8bd1}", systemImage: "waveform") }
                NavigationLink { PiliSuperResolutionSettingsView() } label: { PiliLabel("\u{8d85}\u{5206}\u{8fa8}\u{7387}", systemImage: "sparkles.tv") }
                if detailViewModel.isVideoListenModeEnabled,
                   !detailViewModel.videoListenAudioVariants.isEmpty {
                    NavigationLink {
                        SurfaceOnlyAudioChoicesPage(
                            detailViewModel: detailViewModel,
                            closeSheet: close
                        )
                    } label: {
                        HStack {
                            PiliLabel("\u{97f3}\u{8d28}", systemImage: "waveform")
                            Spacer()
                            Text(detailViewModel.videoListenAudioAccessoryTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if qualityStore.hasQualityMenu {
                    NavigationLink {
                        SurfaceOnlyQualityChoicesPage(
                            qualityStore: qualityStore,
                            closeSheet: close,
                            selectPlayVariant: selectPlayVariant
                        )
                    } label: {
                        HStack {
                            PiliLabel("\u{6e05}\u{6670}\u{5ea6}", systemImage: qualityStore.qualityButtonSystemImage)
                            Spacer()
                            Text(qualityStore.qualityAccessoryButtonTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("ui.player.quality")
                }

                if detailViewModel.isVideoListenModeEnabled {
                    NavigationLink {
                        SurfaceOnlyVideoListenQueuePage(
                            detailViewModel: detailViewModel,
                            closeSheet: close
                        )
                    } label: {
                        HStack {
                            PiliLabel("\u{64ad}\u{653e}\u{5217}\u{8868}", systemImage: "list.bullet")
                            Spacer()
                            Text(detailViewModel.videoListenQueueAccessoryTitle)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        SurfaceOnlyVideoListenPlaybackOrderPage(
                            libraryStore: libraryStore,
                            closeSheet: close
                        )
                    } label: {
                        HStack {
                            PiliLabel("\u{64ad}\u{653e}\u{987a}\u{5e8f}", systemImage: piliPlaybackPreferences.order.systemImage)
                            Spacer()
                            Text(piliPlaybackPreferences.order.title)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        SurfaceOnlyVideoListenSleepTimerPage(
                            detailViewModel: detailViewModel,
                            closeSheet: close
                        )
                    } label: {
                        HStack {
                            PiliLabel("\u{5b9a}\u{65f6}\u{5173}\u{95ed}", systemImage: "timer")
                            Spacer()
                            Text(detailViewModel.videoListenSleepTimerAccessoryTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !detailViewModel.isVideoListenModeEnabled {
                    if let source = detailViewModel.selectedPlayVariant?.videoURL {
                        NavigationLink {
                            PiliMediaCaptureView(source: source, time: viewModel.currentTime, duration: viewModel.duration ?? 0)
                        } label: { PiliLabel("\u{622a}\u{56fe}\u{4e0e}\u{52a8}\u{56fe}", systemImage: "camera") }
                    }
                    NavigationLink {
                        SurfaceOnlyDanmakuSettingsPage(
                            detailViewModel: detailViewModel,
                            toggleDanmaku: onToggleDanmaku
                        )
                    } label: {
                        PiliLabel("\u{5f39}\u{5e55}\u{8bbe}\u{7f6e}", systemImage: "text.bubble")
                    }
                }

                NavigationLink {
                    SurfaceOnlyRateChoicesPage(
                        viewModel: viewModel,
                        closeSheet: close
                    )
                } label: {
                    HStack {
                        PiliLabel("\u{500d}\u{901f}", systemImage: "speedometer")
                        Spacer()
                        Text(viewModel.playbackRate.title)
                            .foregroundStyle(.secondary)
                    }
                }

                if showsVideoListenModeToggle {
                    Toggle(isOn: videoListenModeBinding) {
                        Label {
                            HStack(spacing: 8) {
                                Text("\u{542c}\u{89c6}\u{9891}")
                                if detailViewModel.isSwitchingVideoListenMode {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        } icon: {
                            PiliIcon(systemName: "headphones")
                        }
                    }
                    .disabled(detailViewModel.isSwitchingVideoListenMode)
                }

                if !detailViewModel.isVideoListenModeEnabled {
                    Toggle(isOn: Binding(
                        get: { libraryStore.pictureInPictureEnabled },
                        set: { libraryStore.setPictureInPictureEnabled($0) }
                    )) {
                        PiliLabel("\u{753b}\u{4e2d}\u{753b}\u{64ad}\u{653e}", systemImage: "pip")
                    }
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.playerPerformanceOverlayEnabled },
                    set: { libraryStore.setPlayerPerformanceOverlayEnabled($0) }
                )) {
                    PiliLabel("\u{64ad}\u{653e}\u{6027}\u{80fd}\u{8bca}\u{65ad}", systemImage: "waveform.path.ecg.rectangle")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.playerControlEdgeScrimEnabled },
                    set: { libraryStore.setPlayerControlEdgeScrimEnabled($0) }
                )) {
                    PiliLabel("\u{64ad}\u{653e}\u{63a7}\u{4ef6}\u{8fb9}\u{7f18}\u{906e}\u{7f69}", systemImage: "rectangle.topthird.inset.filled")
                }

                PiliLabel("\(mediaFormatLabel)：\(videoFormatTitle)", systemImage: mediaFormatSystemImage)
                    .foregroundStyle(.secondary)

                PiliLabel("\u{89e3}\u{7801}：\(decodeTitle)", systemImage: "cpu")
                    .foregroundStyle(.secondary)

                Toggle(isOn: Binding(
                    get: { libraryStore.forceHardwareDecodeEnabled },
                    set: { libraryStore.setForceHardwareDecodeEnabled($0) }
                )) {
                    PiliLabel("\u{786c}\u{89e3}\u{4f18}\u{5148}", systemImage: "cpu")
                }

                Picker(selection: Binding(
                    get: { libraryStore.dolbyVisionRenderingPolicy },
                    set: { libraryStore.setDolbyVisionRenderingPolicy($0) }
                )) {
                    ForEach(DolbyVisionRenderingPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                } label: {
                    PiliLabel("\u{675c}\u{6bd4}\u{89c6}\u{754c}\u{6e32}\u{67d3}", systemImage: "sparkles.tv")
                }
                .pickerStyle(.navigationLink)
            }
            .scrollContentBackground(.hidden)
            .listRowBackground(Color.clear)
            .listStyle(.plain)
            .background(Color.clear)
            .foregroundStyle(.primary)
            .navigationTitle("\u{64ad}\u{653e}\u{8bbe}\u{7f6e}")
            .navigationBarTitleDisplayMode(.inline)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var decodeTitle: String {
        SurfaceOnlyPlaybackFormatText.decodeTitle(for: viewModel.engineDiagnostics)
    }

    private var videoFormatTitle: String {
        SurfaceOnlyPlaybackFormatText.videoFormatTitle(for: viewModel.engineDiagnostics)
    }

    private var showsVideoListenModeToggle: Bool {
        detailViewModel.isVideoListenModeEnabled || detailViewModel.canUseVideoListenMode
    }

    private var videoListenModeBinding: Binding<Bool> {
        Binding(
            get: { detailViewModel.isVideoListenModeEnabled },
            set: { detailViewModel.setVideoListenModeEnabled($0) }
        )
    }

    private var mediaFormatLabel: String {
        detailViewModel.isVideoListenModeEnabled ? "\u{97f3}\u{9891}\u{683c}\u{5f0f}" : "\u{89c6}\u{9891}\u{683c}\u{5f0f}"
    }

    private var mediaFormatSystemImage: String {
        detailViewModel.isVideoListenModeEnabled ? "waveform" : "film"
    }

}

private enum SurfaceOnlyPlaybackFormatText {
    static func decodeTitle(for diagnostics: PlayerEngineDiagnostics) -> String {
        var parts = [diagnostics.decodePath.title]
        if diagnostics.hardwareDecodeRequested {
            parts.append("\u{786c}\u{89e3}")
        }
        if let isHardwareDecodeCompatible = diagnostics.isHardwareDecodeCompatible {
            parts.append(isHardwareDecodeCompatible ? "\u{786c}\u{89e3}\u{517c}\u{5bb9}" : "\u{786c}\u{89e3}\u{4e0d}\u{517c}\u{5bb9}")
        }
        return parts.joined(separator: " · ")
    }

    static func videoFormatTitle(for diagnostics: PlayerEngineDiagnostics) -> String {
        var parts = [String]()
        if let codec = diagnostics.codec, !codec.isEmpty {
            parts.append(codecDisplayName(codec))
        }
        if let resolution = diagnostics.resolution, !resolution.isEmpty {
            parts.append(resolution)
        }
        if let frameRate = diagnostics.frameRate, !frameRate.isEmpty {
            parts.append(frameRate)
        }
        if let dynamicRangeTitle = dynamicRangeTitle(for: diagnostics.dynamicRange) {
            parts.append(dynamicRangeTitle)
        }
        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }
        let description = diagnostics.compactDescription
        return description.isEmpty ? "\u{672a}\u{77e5}" : description
    }

    private static func dynamicRangeTitle(for dynamicRange: BiliVideoDynamicRange) -> String? {
        switch dynamicRange {
        case .sdr:
            return nil
        case .hdr10:
            return "HDR"
        case .hlg:
            return "HLG"
        case .dolbyVision:
            return "\u{675c}\u{6bd4}\u{89c6}\u{754c}"
        }
    }

    private static func codecDisplayName(_ codec: String) -> String {
        switch codec.uppercased() {
        case "AVC":
            return "H.264 / AVC"
        case "HEVC":
            return "HEVC / H.265"
        default:
            return codec
        }
    }
}

private struct SurfaceOnlyLandscapeMoreControlsOverlay: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var viewModel: PlayerStateViewModel
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var qualityStore: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let contentInsets: EdgeInsets
    let close: () -> Void
    @State private var page: SurfaceOnlyLandscapeMoreControlsPage = .root

    var body: some View {
        GeometryReader { proxy in
            let visibleFrame = visibleVideoFrame(in: proxy.size)
            let panelSize = landscapePanelSize(in: visibleFrame)
            ZStack {
                Color.black.opacity(0.04)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)

                landscapePanel(size: panelSize)
                    .position(landscapePanelCenter(panelSize: panelSize, visibleFrame: visibleFrame))
                    .contentShape(Rectangle())
                    .onTapGesture {}
            }
        }
    }

    @ViewBuilder
    private func landscapePanel(size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(spacing: 0) {
            SurfaceOnlyLandscapeMoreHeader(
                title: page.title,
                canGoBack: page != .root,
                goBack: { page = .root },
                close: close
            )

            Divider()

            SurfaceOnlyLandscapeMoreContent(
                page: $page,
                detailViewModel: detailViewModel,
                viewModel: viewModel,
                libraryStore: libraryStore,
                qualityStore: qualityStore,
                selectPlayVariant: selectPlayVariant,
                onToggleDanmaku: onToggleDanmaku,
                close: close
            )
        }
        .frame(width: size.width, height: size.height)
        .surfaceOnlyLandscapeGlassPanel(in: shape)
        .clipShape(shape)
        .overlay {
            shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 10)
    }

    private func visibleVideoFrame(in size: CGSize) -> CGRect {
        CGRect(
            x: contentInsets.leading,
            y: contentInsets.top,
            width: max(1, size.width - contentInsets.leading - contentInsets.trailing),
            height: max(1, size.height - contentInsets.top - contentInsets.bottom)
        )
    }

    private func landscapePanelSize(in visibleFrame: CGRect) -> CGSize {
        let horizontalMargin: CGFloat = 18
        let verticalMargin: CGFloat = 14
        let topOffset: CGFloat = 58
        let availableWidth = max(1, visibleFrame.width - horizontalMargin * 2)
        let width = min(330, availableWidth)
        let availableHeight = max(1, visibleFrame.height - topOffset - verticalMargin)
        let height = min(318, availableHeight)
        return CGSize(width: width, height: height)
    }

    private func landscapePanelCenter(panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        let horizontalMargin: CGFloat = 18
        let verticalMargin: CGFloat = 14
        let preferredTop: CGFloat = visibleFrame.minY + 58
        let preferredX = visibleFrame.maxX - horizontalMargin - panelSize.width / 2
        let preferredY = preferredTop + panelSize.height / 2
        return CGPoint(
            x: clamped(
                preferredX,
                lower: visibleFrame.minX + horizontalMargin + panelSize.width / 2,
                upper: visibleFrame.maxX - horizontalMargin - panelSize.width / 2,
                fallback: visibleFrame.midX
            ),
            y: clamped(
                preferredY,
                lower: visibleFrame.minY + verticalMargin + panelSize.height / 2,
                upper: visibleFrame.maxY - verticalMargin - panelSize.height / 2,
                fallback: visibleFrame.midY
            )
        )
    }

    private func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat, fallback: CGFloat) -> CGFloat {
        guard lower <= upper else { return fallback }
        return min(max(value, lower), upper)
    }

}

private enum SurfaceOnlyLandscapeMoreControlsPage {
    case root
    case quality
    case audio
    case queue
    case playbackOrder
    case sleepTimer
    case danmaku
    case capture
    case language
    case superResolution
    case rate

    var title: String {
        switch self {
        case .root:
            return "\u{64ad}\u{653e}\u{8bbe}\u{7f6e}"
        case .quality:
            return "\u{6e05}\u{6670}\u{5ea6}"
        case .audio:
            return "\u{97f3}\u{8d28}"
        case .queue:
            return "\u{64ad}\u{653e}\u{5217}\u{8868}"
        case .playbackOrder:
            return "\u{64ad}\u{653e}\u{987a}\u{5e8f}"
        case .sleepTimer:
            return "\u{5b9a}\u{65f6}\u{5173}\u{95ed}"
        case .danmaku:
            return "\u{5f39}\u{5e55}\u{8bbe}\u{7f6e}"
        case .capture: return "\u{622a}\u{56fe}\u{4e0e}\u{52a8}\u{56fe}"
        case .language: return "\u{539f}\u{58f0}\u{7ffb}\u{8bd1}"
        case .superResolution: return "\u{8d85}\u{5206}\u{8fa8}\u{7387}"
        case .rate:
            return "\u{500d}\u{901f}"
        }
    }
}

private struct SurfaceOnlyLandscapeMoreHeader: View {
    let title: String
    let canGoBack: Bool
    let goBack: () -> Void
    let close: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .piliFont(.baseBold)
                .foregroundStyle(.primary)
                .lineLimit(1)

            HStack {
                if canGoBack {
                    Button(action: goBack) {
                        PiliIcon(systemName: "chevron.left", size: 15)
                            .piliFont(.baseBold)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .contentShape(Circle())
                    .accessibilityLabel("\u{8fd4}\u{56de}")
                }

                Spacer()

                Button(action: close) {
                    PiliIcon(systemName: "xmark", size: 13)
                        .piliFont(.smBold)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .contentShape(Circle())
                .accessibilityLabel("\u{5173}\u{95ed}")
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 12)
    }
}

private struct SurfaceOnlyLandscapeMoreContent: View {
    @ObservedObject private var piliPlaybackPreferences = PiliPlaybackPreferences.shared
    @Binding var page: SurfaceOnlyLandscapeMoreControlsPage
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var viewModel: PlayerStateViewModel
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var qualityStore: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let close: () -> Void

    var body: some View {
        Group {
            switch page {
            case .root:
                rootPage
            case .quality:
                qualityPage
            case .audio:
                audioPage
            case .queue:
                queuePage
            case .playbackOrder:
                playbackOrderPage
            case .sleepTimer:
                sleepTimerPage
            case .danmaku:
                SurfaceOnlyDanmakuSettingsPage(
                    detailViewModel: detailViewModel,
                    toggleDanmaku: onToggleDanmaku
                )
                .scrollContentBackground(.hidden)
            case .rate:
                ratePage
            case .language:
                PiliAudioLanguageView(viewModel: detailViewModel).scrollContentBackground(.hidden)
            case .superResolution:
                PiliSuperResolutionSettingsView().scrollContentBackground(.hidden)
            case .capture:
                if let source = detailViewModel.selectedPlayVariant?.videoURL {
                    PiliMediaCaptureView(source: source, time: viewModel.currentTime, duration: viewModel.duration ?? 0)
                }
            }
        }
    }

    private var rootPage: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(spacing: 0) {
                    SurfaceOnlyLandscapeMenuRow(title: "\u{539f}\u{58f0}\u{7ffb}\u{8bd1}", systemImage: "waveform", accessory: nil, showsChevron: true) { page = .language }
                    SurfaceOnlyLandscapeMenuRow(title: "\u{8d85}\u{5206}\u{8fa8}\u{7387}", systemImage: "sparkles.tv", accessory: nil, showsChevron: true) { page = .superResolution }
                    if !detailViewModel.isVideoListenModeEnabled {
                        SurfaceOnlyLandscapeMenuRow(title: "\u{622a}\u{56fe}\u{4e0e}\u{52a8}\u{56fe}", systemImage: "camera", accessory: nil, showsChevron: true) { page = .capture }
                    }
                    if detailViewModel.isVideoListenModeEnabled,
                       !detailViewModel.videoListenAudioVariants.isEmpty {
                        SurfaceOnlyLandscapeMenuRow(
                            title: "\u{97f3}\u{8d28}",
                            systemImage: "waveform",
                            accessory: detailViewModel.videoListenAudioAccessoryTitle,
                            showsChevron: true
                        ) {
                            page = .audio
                        }

                        Divider().padding(.leading, 44)
                    } else if qualityStore.hasQualityMenu {
                        SurfaceOnlyLandscapeMenuRow(
                            title: "\u{6e05}\u{6670}\u{5ea6}",
                            systemImage: qualityStore.qualityButtonSystemImage,
                            accessory: qualityStore.qualityAccessoryButtonTitle,
                            showsChevron: true
                        ) {
                            page = .quality
                        }

                        Divider().padding(.leading, 44)
                    }

                    if detailViewModel.isVideoListenModeEnabled {
                        SurfaceOnlyLandscapeMenuRow(
                            title: "\u{64ad}\u{653e}\u{5217}\u{8868}",
                            systemImage: "list.bullet",
                            accessory: detailViewModel.videoListenQueueAccessoryTitle,
                            showsChevron: true
                        ) {
                            page = .queue
                        }

                        Divider().padding(.leading, 44)

                        SurfaceOnlyLandscapeMenuRow(
                            title: "\u{64ad}\u{653e}\u{987a}\u{5e8f}",
                            systemImage: piliPlaybackPreferences.order.systemImage,
                            accessory: piliPlaybackPreferences.order.title,
                            showsChevron: true
                        ) {
                            page = .playbackOrder
                        }

                        Divider().padding(.leading, 44)

                        SurfaceOnlyLandscapeMenuRow(
                            title: "\u{5b9a}\u{65f6}\u{5173}\u{95ed}",
                            systemImage: "timer",
                            accessory: detailViewModel.videoListenSleepTimerAccessoryTitle,
                            showsChevron: true
                        ) {
                            page = .sleepTimer
                        }

                        Divider().padding(.leading, 44)
                    }

                    if !detailViewModel.isVideoListenModeEnabled {
                        SurfaceOnlyLandscapeMenuRow(
                            title: "\u{5f39}\u{5e55}\u{8bbe}\u{7f6e}",
                            systemImage: "text.bubble",
                            accessory: nil,
                            showsChevron: true
                        ) {
                            page = .danmaku
                        }

                        Divider().padding(.leading, 44)
                    }

                    SurfaceOnlyLandscapeMenuRow(
                        title: "\u{500d}\u{901f}",
                        systemImage: "speedometer",
                        accessory: viewModel.playbackRate.title,
                        showsChevron: true
                    ) {
                        page = .rate
                    }

                    Divider().padding(.leading, 44)

                    if showsVideoListenModeToggle {
                        SurfaceOnlyLandscapeToggleRow(
                            title: "\u{542c}\u{89c6}\u{9891}",
                            systemImage: "headphones",
                            accessory: videoListenModeAccessory,
                            isOn: videoListenModeBinding
                        )
                        .disabled(detailViewModel.isSwitchingVideoListenMode)

                        Divider().padding(.leading, 44)
                    }

                    if !detailViewModel.isVideoListenModeEnabled {
                        SurfaceOnlyLandscapeToggleRow(
                            title: "\u{753b}\u{4e2d}\u{753b}\u{64ad}\u{653e}",
                            systemImage: "pip",
                            accessory: pictureInPictureAccessory,
                            isOn: Binding(
                                get: { libraryStore.pictureInPictureEnabled },
                                set: { libraryStore.setPictureInPictureEnabled($0) }
                            )
                        )

                        Divider().padding(.leading, 44)
                    }

                    SurfaceOnlyLandscapeToggleRow(
                        title: "\u{64ad}\u{653e}\u{6027}\u{80fd}\u{8bca}\u{65ad}",
                        systemImage: "waveform.path.ecg.rectangle",
                        accessory: performanceOverlayAccessory,
                        isOn: Binding(
                            get: { libraryStore.playerPerformanceOverlayEnabled },
                            set: { libraryStore.setPlayerPerformanceOverlayEnabled($0) }
                        )
                    )

                    Divider().padding(.leading, 44)

                    SurfaceOnlyLandscapeToggleRow(
                        title: "\u{64ad}\u{653e}\u{63a7}\u{4ef6}\u{8fb9}\u{7f18}\u{906e}\u{7f69}",
                        systemImage: "rectangle.topthird.inset.filled",
                        accessory: controlEdgeScrimAccessory,
                        isOn: Binding(
                            get: { libraryStore.playerControlEdgeScrimEnabled },
                            set: { libraryStore.setPlayerControlEdgeScrimEnabled($0) }
                        )
                    )
                }
                .surfaceOnlyLandscapeGlassGroup()

                VStack(spacing: 0) {
                    SurfaceOnlyLandscapeInfoRow(
                        title: mediaFormatLabel,
                        systemImage: mediaFormatSystemImage,
                        value: videoFormatTitle
                    )

                    Divider().padding(.leading, 44)

                    SurfaceOnlyLandscapeInfoRow(
                        title: "\u{89e3}\u{7801}",
                        systemImage: "cpu",
                        value: decodeTitle
                    )
                }
                .surfaceOnlyLandscapeGlassGroup()
            }
            .padding(12)
        }
    }

    private var qualityPage: some View {
        ScrollView {
            VStack(spacing: 10) {
                if qualityStore.isSwitchingPlayQuality {
                    SurfaceOnlyQualitySwitchingIndicator()
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .surfaceOnlyLandscapeGlassGroup()
                }

                VStack(spacing: 0) {
                    ForEach(Array(qualityStore.qualityMenuItems.enumerated()), id: \.element.id) { index, item in
                        SurfaceOnlyLandscapeMenuRow(
                            title: item.title,
                            subtitle: item.subtitle,
                            systemImage: item.systemImage,
                            accessory: nil,
                            showsChevron: false
                        ) {
                            selectPlayVariant(item.variant)
                            close()
                        }
                        .disabled(item.isDisabled)
                        .opacity(item.isDisabled ? 0.45 : 1)

                        if index < qualityStore.qualityMenuItems.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .surfaceOnlyLandscapeGlassGroup()
            }
            .padding(12)
        }
    }

    private var audioPage: some View {
        ScrollView {
            VStack(spacing: 10) {
                if detailViewModel.isSwitchingVideoListenMode {
                    SurfaceOnlyAudioSwitchingIndicator()
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .surfaceOnlyLandscapeGlassGroup()
                }

                VStack(spacing: 0) {
                    SurfaceOnlyLandscapeMenuRow(
                        title: "\u{81ea}\u{52a8}",
                        subtitle: automaticAudioSubtitle,
                        systemImage: detailViewModel.selectedVideoListenAudioPreferenceKey == nil
                            ? "checkmark"
                            : "wand.and.stars",
                        accessory: nil,
                        showsChevron: false
                    ) {
                        detailViewModel.selectVideoListenAudioVariant(nil)
                        close()
                    }

                    if !detailViewModel.videoListenAudioVariants.isEmpty {
                        Divider().padding(.leading, 44)
                    }

                    ForEach(Array(detailViewModel.videoListenAudioVariants.enumerated()), id: \.element.id) { index, variant in
                        SurfaceOnlyLandscapeMenuRow(
                            title: variant.title,
                            subtitle: variant.subtitle,
                            systemImage: detailViewModel.selectedVideoListenAudioPreferenceKey == variant.preferenceKey
                                ? "checkmark"
                                : variant.systemImage,
                            accessory: nil,
                            showsChevron: false
                        ) {
                            detailViewModel.selectVideoListenAudioVariant(variant)
                            close()
                        }

                        if index < detailViewModel.videoListenAudioVariants.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .surfaceOnlyLandscapeGlassGroup()
            }
            .padding(12)
        }
    }

    private var ratePage: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(BiliPlaybackRate.allCases.enumerated()), id: \.element.id) { index, rate in
                    SurfaceOnlyLandscapeMenuRow(
                        title: rate.title,
                        systemImage: rate == viewModel.playbackRate ? "checkmark" : "speedometer",
                        accessory: nil,
                        showsChevron: false
                    ) {
                        viewModel.setPlaybackRate(rate)
                        close()
                    }

                    if index < BiliPlaybackRate.allCases.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .surfaceOnlyLandscapeGlassGroup()
            .padding(12)
        }
    }

    private var queuePage: some View {
        ScrollView {
            if detailViewModel.videoListenQueueEntries.isEmpty {
                VStack(spacing: 10) {
                    if detailViewModel.isLoadingVideoListenQueue {
                        ProgressView()
                            .controlSize(.small)
                        Text("\u{6b63}\u{5728}\u{8f7d}\u{5165}\u{64ad}\u{653e}\u{5217}\u{8868}")
                            .piliFont(.base)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(detailViewModel.videoListenQueueLoadFailed ? "\u{64ad}\u{653e}\u{5217}\u{8868}\u{8f7d}\u{5165}\u{5931}\u{8d25}" : "\u{6ca1}\u{6709}\u{53ef}\u{64ad}\u{653e}\u{5185}\u{5bb9}")
                            .piliFont(.base)
                            .foregroundStyle(.secondary)
                        if detailViewModel.videoListenQueueLoadFailed {
                            Button("\u{91cd}\u{65b0}\u{8f7d}\u{5165}") {
                                Task {
                                    await detailViewModel.prepareVideoListenQueue()
                                }
                            }
                            .piliFont(.base).fontWeight(.semibold)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .surfaceOnlyLandscapeGlassGroup()
                .padding(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(detailViewModel.videoListenQueueEntries.enumerated()), id: \.element.id) { index, entry in
                        SurfaceOnlyLandscapeMenuRow(
                            title: entry.title,
                            subtitle: entry.subtitle,
                            systemImage: entry.isCurrent ? "checkmark.circle.fill" : "play.circle",
                            accessory: entry.isCurrent ? "\u{6b63}\u{5728}\u{64ad}\u{653e}" : nil,
                            showsChevron: false
                        ) {
                            detailViewModel.selectVideoListenQueueEntry(entry)
                            close()
                        }
                        .task {
                            await detailViewModel.loadMoreVideoListenQueueIfNeeded(current: entry)
                        }

                        if index < detailViewModel.videoListenQueueEntries.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }

                    if detailViewModel.isLoadingVideoListenQueue {
                        Divider().padding(.leading, 44)
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("\u{6b63}\u{5728}\u{8f7d}\u{5165}\u{66f4}\u{591a}\u{89c6}\u{9891}")
                                .piliFont(.base)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else if detailViewModel.videoListenQueueLoadFailed,
                              detailViewModel.videoListenQueueEntries.count <= 1 {
                        Divider().padding(.leading, 44)
                        Button("\u{91cd}\u{65b0}\u{8f7d}\u{5165}\u{64ad}\u{653e}\u{5217}\u{8868}") {
                            Task {
                                await detailViewModel.prepareVideoListenQueue()
                            }
                        }
                        .piliFont(.base).fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else if detailViewModel.videoListenQueueSession.isLoadingMore {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .surfaceOnlyLandscapeGlassGroup()
                .padding(12)
            }
        }
        .task {
            await detailViewModel.prepareVideoListenQueue()
        }
    }

    private var playbackOrderPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(PlaybackOrder.allCases.enumerated()), id: \.element.rawValue) { index, order in
                    SurfaceOnlyLandscapeMenuRow(
                        title: order.title,
                        subtitle: order.subtitle,
                        systemImage: piliPlaybackPreferences.order == order
                            ? "checkmark.circle.fill"
                            : order.systemImage,
                        accessory: nil,
                        showsChevron: false
                    ) {
                        piliPlaybackPreferences.setOrder(order)
                        close()
                    }

                    if index < PlaybackOrder.allCases.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .surfaceOnlyLandscapeGlassGroup()
            .padding(12)
        }
    }

    private var sleepTimerPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(VideoListenSleepTimerOption.allCases.enumerated()), id: \.element.id) { index, option in
                    SurfaceOnlyLandscapeMenuRow(
                        title: option.title,
                        systemImage: detailViewModel.isPiliSleepTimerOptionSelected(option)
                            ? "checkmark.circle.fill"
                            : option.systemImage,
                        accessory: nil,
                        showsChevron: false
                    ) {
                        detailViewModel.setVideoListenSleepTimer(option)
                        close()
                    }

                    if index < VideoListenSleepTimerOption.allCases.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .surfaceOnlyLandscapeGlassGroup()
            .padding(12)
        }
    }

    private var decodeTitle: String {
        SurfaceOnlyPlaybackFormatText.decodeTitle(for: viewModel.engineDiagnostics)
    }

    private var videoFormatTitle: String {
        SurfaceOnlyPlaybackFormatText.videoFormatTitle(for: viewModel.engineDiagnostics)
    }

    private var pictureInPictureAccessory: String? {
        return libraryStore.pictureInPictureEnabled ? "\u{5df2}\u{5f00}\u{542f}" : "\u{5df2}\u{5173}\u{95ed}"
    }

    private var showsVideoListenModeToggle: Bool {
        detailViewModel.isVideoListenModeEnabled || detailViewModel.canUseVideoListenMode
    }

    private var videoListenModeBinding: Binding<Bool> {
        Binding(
            get: { detailViewModel.isVideoListenModeEnabled },
            set: { detailViewModel.setVideoListenModeEnabled($0) }
        )
    }

    private var videoListenModeAccessory: String? {
        if detailViewModel.isSwitchingVideoListenMode {
            return "\u{5207}\u{6362}\u{4e2d}"
        }
        return detailViewModel.isVideoListenModeEnabled ? "\u{5df2}\u{5f00}\u{542f}" : "\u{5df2}\u{5173}\u{95ed}"
    }

    private var automaticAudioSubtitle: String {
        guard let variant = detailViewModel.automaticVideoListenAudioVariant else {
            return "\u{4f18}\u{5148}\u{9009}\u{62e9}\u{517c}\u{5bb9}\u{6027}\u{8f83}\u{597d}\u{7684}\u{97f3}\u{8f68}"
        }
        return ["\u{5f53}\u{524d} \(variant.title)", variant.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var mediaFormatLabel: String {
        detailViewModel.isVideoListenModeEnabled ? "\u{97f3}\u{9891}\u{683c}\u{5f0f}" : "\u{89c6}\u{9891}\u{683c}\u{5f0f}"
    }

    private var mediaFormatSystemImage: String {
        detailViewModel.isVideoListenModeEnabled ? "waveform" : "film"
    }

    private var performanceOverlayAccessory: String? {
        return libraryStore.playerPerformanceOverlayEnabled ? "\u{5df2}\u{5f00}\u{542f}" : "\u{5df2}\u{5173}\u{95ed}"
    }

    private var controlEdgeScrimAccessory: String? {
        return libraryStore.playerControlEdgeScrimEnabled ? "\u{5df2}\u{5f00}\u{542f}" : "\u{5df2}\u{5173}\u{95ed}"
    }
}

private struct SurfaceOnlyLandscapeToggleRow: View {
    let title: String
    let systemImage: String
    let accessory: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                PiliIcon(systemName: systemImage, size: 16)
                    .piliFont(.baseBold)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                Text(title)
                    .piliFont(.base)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let accessory {
                    Text(accessory)
                        .piliFont(.base)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: 44)
            .padding(.leading, 12)
        }
        .toggleStyle(.switch)
        .padding(.trailing, 12)
        .contentShape(Rectangle())
    }
}

private struct SurfaceOnlyLandscapeMenuRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let accessory: String?
    let showsChevron: Bool
    let action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        accessory: String?,
        showsChevron: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accessory = accessory
        self.showsChevron = showsChevron
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                PiliIcon(systemName: systemImage, size: 16)
                    .piliFont(.baseBold)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .piliFont(.base)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .piliFont(.sm)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let accessory {
                    Text(accessory)
                        .piliFont(.base)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if showsChevron {
                    PiliIcon(systemName: "chevron.right")
                        .piliFont(.sm).fontWeight(.semibold)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SurfaceOnlyLandscapeInfoRow: View {
    let title: String
    let systemImage: String
    let value: String?

    var body: some View {
        HStack(spacing: 12) {
            PiliIcon(systemName: systemImage, size: 16)
                .piliFont(.baseBold)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(title)
                .piliFont(.base)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let value {
                Text(value)
                    .piliFont(.base)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
    }
}

private struct SurfaceOnlyQualityChoicesPage: View {
    @ObservedObject var qualityStore: VideoDetailQualityControlRenderStore
    let closeSheet: () -> Void
    let selectPlayVariant: (PlayVariant) -> Void

    var body: some View {
        PiliList {
            if qualityStore.isSwitchingPlayQuality {
                SurfaceOnlyQualitySwitchingIndicator()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            ForEach(qualityStore.qualityMenuItems) { item in
                Button {
                    selectPlayVariant(item.variant)
                    closeSheet()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            if let subtitle = item.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .piliFont(.sm)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        PiliIcon(systemName: item.systemImage)
                    }
                }
                .disabled(item.isDisabled)
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .foregroundStyle(.primary)
        .navigationTitle("\u{6e05}\u{6670}\u{5ea6}")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
    }
}

private struct SurfaceOnlyAudioChoicesPage: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    let closeSheet: () -> Void

    var body: some View {
        PiliList {
            if detailViewModel.isSwitchingVideoListenMode {
                SurfaceOnlyAudioSwitchingIndicator()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            Button {
                detailViewModel.selectVideoListenAudioVariant(nil)
                closeSheet()
            } label: {
                audioChoiceLabel(
                    title: "\u{81ea}\u{52a8}",
                    subtitle: automaticSubtitle,
                    systemImage: detailViewModel.selectedVideoListenAudioPreferenceKey == nil
                        ? "checkmark"
                        : "wand.and.stars"
                )
            }

            ForEach(detailViewModel.videoListenAudioVariants) { variant in
                Button {
                    detailViewModel.selectVideoListenAudioVariant(variant)
                    closeSheet()
                } label: {
                    audioChoiceLabel(
                        title: variant.title,
                        subtitle: variant.subtitle,
                        systemImage: detailViewModel.selectedVideoListenAudioPreferenceKey == variant.preferenceKey
                            ? "checkmark"
                            : variant.systemImage
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .foregroundStyle(.primary)
        .navigationTitle("\u{97f3}\u{8d28}")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
    }

    private func audioChoiceLabel(
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .piliFont(.sm)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            PiliIcon(systemName: systemImage)
        }
    }

    private var automaticSubtitle: String {
        guard let variant = detailViewModel.automaticVideoListenAudioVariant else {
            return "\u{4f18}\u{5148}\u{9009}\u{62e9}\u{517c}\u{5bb9}\u{6027}\u{8f83}\u{597d}\u{7684}\u{97f3}\u{8f68}"
        }
        return ["\u{5f53}\u{524d} \(variant.title)", variant.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private struct SurfaceOnlyVideoListenQueuePage: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    let closeSheet: () -> Void

    var body: some View {
        PiliList {
            if detailViewModel.videoListenQueueEntries.isEmpty {
                VStack(spacing: 10) {
                    if detailViewModel.isLoadingVideoListenQueue {
                        ProgressView()
                            .controlSize(.small)
                        Text("\u{6b63}\u{5728}\u{8f7d}\u{5165}\u{64ad}\u{653e}\u{5217}\u{8868}")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(detailViewModel.videoListenQueueLoadFailed ? "\u{64ad}\u{653e}\u{5217}\u{8868}\u{8f7d}\u{5165}\u{5931}\u{8d25}" : "\u{6ca1}\u{6709}\u{53ef}\u{64ad}\u{653e}\u{5185}\u{5bb9}")
                            .foregroundStyle(.secondary)
                        if detailViewModel.videoListenQueueLoadFailed {
                            Button("\u{91cd}\u{65b0}\u{8f7d}\u{5165}") {
                                Task {
                                    await detailViewModel.prepareVideoListenQueue()
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(detailViewModel.videoListenQueueEntries) { entry in
                    Button {
                        detailViewModel.selectVideoListenQueueEntry(entry)
                        closeSheet()
                    } label: {
                        Label {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                    if let subtitle = entry.subtitle {
                                        Text(subtitle)
                                            .piliFont(.sm)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if entry.isCurrent {
                                    Text("\u{6b63}\u{5728}\u{64ad}\u{653e}")
                                        .piliFont(.sm)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            PiliIcon(systemName: entry.isCurrent ? "checkmark.circle.fill" : "play.circle")
                        }
                    }
                    .task {
                        await detailViewModel.loadMoreVideoListenQueueIfNeeded(current: entry)
                    }
                }

                if detailViewModel.isLoadingVideoListenQueue {
                    HStack(spacing: 8) {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Text("\u{6b63}\u{5728}\u{8f7d}\u{5165}\u{66f4}\u{591a}\u{89c6}\u{9891}")
                            .piliFont(.base)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else if detailViewModel.videoListenQueueLoadFailed,
                          detailViewModel.videoListenQueueEntries.count <= 1 {
                    Button("\u{91cd}\u{65b0}\u{8f7d}\u{5165}\u{64ad}\u{653e}\u{5217}\u{8868}") {
                        Task {
                            await detailViewModel.prepareVideoListenQueue()
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else if detailViewModel.videoListenQueueSession.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .foregroundStyle(.primary)
        .navigationTitle("\u{64ad}\u{653e}\u{5217}\u{8868}")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
        .task {
            await detailViewModel.prepareVideoListenQueue()
        }
    }
}

private struct SurfaceOnlyVideoListenPlaybackOrderPage: View {
    @ObservedObject private var piliPlaybackPreferences = PiliPlaybackPreferences.shared
    @ObservedObject var libraryStore: LibraryStore
    let closeSheet: () -> Void

    var body: some View {
        PiliList {
            ForEach(PlaybackOrder.allCases, id: \.rawValue) { order in
                Button {
                    piliPlaybackPreferences.setOrder(order)
                    closeSheet()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(order.title)
                            Text(order.subtitle)
                                .piliFont(.sm)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        PiliIcon(systemName: piliPlaybackPreferences.order == order
                            ? "checkmark.circle.fill"
                            : order.systemImage)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .foregroundStyle(.primary)
        .navigationTitle("\u{64ad}\u{653e}\u{987a}\u{5e8f}")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
    }
}

private struct SurfaceOnlyVideoListenSleepTimerPage: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    let closeSheet: () -> Void

    var body: some View {
        PiliList {
            ForEach(VideoListenSleepTimerOption.allCases) { option in
                Button {
                    detailViewModel.setVideoListenSleepTimer(option)
                    closeSheet()
                } label: {
                    PiliLabel(
                        option.title,
                        systemImage: detailViewModel.isPiliSleepTimerOptionSelected(option)
                            ? "checkmark.circle.fill"
                            : option.systemImage
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .foregroundStyle(.primary)
        .navigationTitle("\u{5b9a}\u{65f6}\u{5173}\u{95ed}")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
    }
}

private struct SurfaceOnlyQualitySwitchingIndicator: View {
    var body: some View {
        PlayerInlineLoadingIndicator(message: "\u{6b63}\u{5728}\u{5207}\u{6362}\u{6e05}\u{6670}\u{5ea6}")
            .accessibilityLabel("\u{6b63}\u{5728}\u{5207}\u{6362}\u{6e05}\u{6670}\u{5ea6}")
    }
}

private struct SurfaceOnlyAudioSwitchingIndicator: View {
    var body: some View {
        PlayerInlineLoadingIndicator(message: "\u{6b63}\u{5728}\u{5207}\u{6362}\u{97f3}\u{8d28}")
            .accessibilityLabel("\u{6b63}\u{5728}\u{5207}\u{6362}\u{97f3}\u{8d28}")
    }
}

private struct SurfaceOnlyDanmakuSettingsPage: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    let toggleDanmaku: () -> Void

    var body: some View {
        DanmakuSettingsSheetContent(
            store: detailViewModel.danmakuSettingsRenderStore,
            summary: settingsSummary,
            displayAreaBinding: displayAreaBinding,
            hidesDanmakuInPortraitBinding: hidesDanmakuInPortraitBinding,
            mergesDuplicatesBinding: Binding(get: { detailViewModel.danmakuSettings.mergesDuplicates }, set: { value in
                var settings = detailViewModel.danmakuSettings
                settings.mergesDuplicates = value
                detailViewModel.updateDanmakuSettings(settings)
            }),
            fontScaleBinding: fontScaleBinding,
            fontWeightBinding: fontWeightBinding,
            opacityBinding: opacityBinding,
            toggleDanmaku: toggleDanmaku,
            updateExtendedSettings: detailViewModel.updateDanmakuSettings
        )
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .navigationTitle("\u{5f39}\u{5e55}\u{8bbe}\u{7f6e}")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
    }

    private var settingsSummary: String {
        let store = detailViewModel.danmakuSettingsRenderStore
        if store.isDanmakuEnabled {
            return "\u{5f53}\u{524d}\u{4f7f}\u{7528} \(store.danmakuSettings.displayArea.title)，\u{5b57}\u{53f7} \(Int((store.danmakuSettings.fontScale * 100).rounded()))%，\u{4e0d}\u{900f}\u{660e}\u{5ea6} \(Int((store.danmakuSettings.opacity * 100).rounded()))%。"
        }
        return "\u{5f39}\u{5e55}\u{5df2}\u{5173}\u{95ed}，\u{64ad}\u{653e}\u{65f6}\u{4e0d}\u{4f1a}\u{663e}\u{793a}\u{6eda}\u{52a8}\u{8bc4}\u{8bba}。"
    }

    private var displayAreaBinding: Binding<DanmakuDisplayArea> {
        Binding(
            get: { detailViewModel.danmakuSettingsRenderStore.danmakuSettings.displayArea },
            set: { newValue in
                var settings = detailViewModel.danmakuSettingsRenderStore.danmakuSettings
                settings.displayArea = newValue
                detailViewModel.updateDanmakuSettings(settings)
            }
        )
    }

    private var fontScaleBinding: Binding<Double> {
        Binding(
            get: { detailViewModel.danmakuSettingsRenderStore.danmakuSettings.fontScale },
            set: { newValue in
                var settings = detailViewModel.danmakuSettingsRenderStore.danmakuSettings
                settings.fontScale = newValue
                detailViewModel.updateDanmakuSettings(settings)
            }
        )
    }

    private var hidesDanmakuInPortraitBinding: Binding<Bool> {
        Binding(
            get: { detailViewModel.danmakuSettingsRenderStore.danmakuSettings.hidesInPortrait },
            set: { newValue in
                var settings = detailViewModel.danmakuSettingsRenderStore.danmakuSettings
                settings.hidesInPortrait = newValue
                detailViewModel.updateDanmakuSettings(settings)
            }
        )
    }

    private var fontWeightBinding: Binding<DanmakuFontWeightOption> {
        Binding(
            get: { detailViewModel.danmakuSettingsRenderStore.danmakuSettings.fontWeight },
            set: { newValue in
                var settings = detailViewModel.danmakuSettingsRenderStore.danmakuSettings
                settings.fontWeight = newValue
                detailViewModel.updateDanmakuSettings(settings)
            }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { detailViewModel.danmakuSettingsRenderStore.danmakuSettings.opacity },
            set: { newValue in
                var settings = detailViewModel.danmakuSettingsRenderStore.danmakuSettings
                settings.opacity = newValue
                detailViewModel.updateDanmakuSettings(settings)
            }
        )
    }
}

private struct SurfaceOnlyUIKitMoreControlsButton: UIViewRepresentable {
    let metrics: PlayerNativeControlMetrics
    let systemImageName: String
    let usesGlass: Bool
    let onPressBegan: () -> Void
    let onPressEnded: () -> Void
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPressBegan: onPressBegan,
            onPressEnded: onPressEnded,
            action: action
        )
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(
            configuration: configuration,
            primaryAction: context.coordinator.primaryAction
        )
        configure(button)
        button.addAction(context.coordinator.pressBeganAction, for: .touchDown)
        button.addAction(
            context.coordinator.pressEndedAction,
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        button.accessibilityLabel = "\u{66f4}\u{591a}\u{64ad}\u{653e}\u{8bbe}\u{7f6e}"
        button.accessibilityIdentifier = "ui.player.more"
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.onPressBegan = onPressBegan
        context.coordinator.onPressEnded = onPressEnded
        context.coordinator.action = action
        configure(button)
    }

    private var configuration: UIButton.Configuration {
        var configuration = usesGlass ? UIButton.Configuration.clearGlass() : UIButton.Configuration.plain()
        configuration.baseForegroundColor = .white
        configuration.contentInsets = .zero
        return configuration
    }

    private func configure(_ button: UIButton) {
        button.configuration = configuration
        button.tintColor = .white

        let iconView: UIImageView
        if let existingIconView = button.viewWithTag(Self.iconViewTag) as? UIImageView {
            iconView = existingIconView
        } else {
            iconView = UIImageView()
            iconView.tag = Self.iconViewTag
            iconView.contentMode = .center
            iconView.tintColor = .white
            iconView.isUserInteractionEnabled = false
            iconView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(iconView)
            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
        }

        let renderer = ImageRenderer(content:
            PiliIcon(systemName: systemImageName, size: metrics.iconSize).foregroundStyle(.white)
        )
        renderer.scale = button.traitCollection.displayScale
        iconView.image = renderer.uiImage
    }

    private static let iconViewTag = 1_634_081

    final class Coordinator {
        var onPressBegan: () -> Void
        var onPressEnded: () -> Void
        var action: () -> Void

        init(
            onPressBegan: @escaping () -> Void,
            onPressEnded: @escaping () -> Void,
            action: @escaping () -> Void
        ) {
            self.onPressBegan = onPressBegan
            self.onPressEnded = onPressEnded
            self.action = action
        }

        lazy var pressBeganAction = UIAction { [weak self] _ in
            self?.onPressBegan()
        }

        lazy var pressEndedAction = UIAction { [weak self] _ in
            self?.onPressEnded()
        }

        lazy var primaryAction = UIAction { [weak self] _ in
            self?.action()
        }
    }
}

private struct VideoDetailFullscreenClockControl: View {

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(context.date, format: .dateTime.hour().minute())
                .piliFont(.sm).monospacedDigit().fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: PlayerNativeControlMetrics.landscape.controlHeight)
        }
        .biliPlayerClearGlass(
            interactive: false,
            in: Capsule(),
            isEnabled: true
        )
        .biliLiquidGlassForeground(shadowOpacity: 0.20)
        .allowsHitTesting(false)
        .accessibilityLabel("\u{7cfb}\u{7edf}\u{65f6}\u{95f4}")
    }
}

private struct VideoDetailFullscreenBatteryControl: View {
    @State private var batteryLevel: Float = -1

    var body: some View {
        HStack(spacing: 4) {
            Text(percentageText)
                .monospacedDigit()
            PiliIcon(systemName: batterySymbolName)
        }
        .piliFont(.sm).fontWeight(.semibold)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: PlayerNativeControlMetrics.landscape.controlHeight)
        .biliPlayerClearGlass(
            interactive: false,
            in: Capsule(),
            isEnabled: true
        )
        .biliLiquidGlassForeground(shadowOpacity: 0.20)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\u{8bbe}\u{5907}\u{7535}\u{91cf} \(percentageText)")
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            updateBatteryLevel()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            updateBatteryLevel()
        }
        .onDisappear {
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
    }

    private var percentage: Int? {
        guard batteryLevel >= 0 else { return nil }
        return min(max(Int((batteryLevel * 100).rounded()), 0), 100)
    }

    private var percentageText: String {
        percentage.map { "\($0)%" } ?? "--%"
    }

    private var batterySymbolName: String {
        guard let percentage else { return "battery.0percent" }
        switch percentage {
        case 76...:
            return "battery.100percent"
        case 51...:
            return "battery.75percent"
        case 26...:
            return "battery.50percent"
        case 1...:
            return "battery.25percent"
        default:
            return "battery.0percent"
        }
    }

    private func updateBatteryLevel() {
        batteryLevel = UIDevice.current.batteryLevel
    }
}

private extension View {
    @ViewBuilder
    func surfaceOnlyLandscapeGlassPanel<S: Shape>(in shape: S) -> some View {
        self
            .background(Color.cc.background.opacity(0.22), in: shape)
            .biliGlassEffect(
                interactive: false,
                in: shape
            )
    }

    @ViewBuilder
    func surfaceOnlyLandscapeGlassGroup() -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        self
            .background(Color.cc.card.opacity(0.34), in: shape)
            .biliPlayerClearGlass(interactive: false, in: shape)
    }
}

private struct SurfaceOnlyRateChoicesPage: View {
    @ObservedObject var viewModel: PlayerStateViewModel
    let closeSheet: () -> Void

    var body: some View {
        PiliList {
            ForEach(BiliPlaybackRate.allCases) { rate in
                Button {
                    viewModel.setPlaybackRate(rate)
                    closeSheet()
                } label: {
                    PiliLabel(
                        rate.title,
                        systemImage: rate == viewModel.playbackRate ? "checkmark" : "speedometer"
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .foregroundStyle(.primary)
        .navigationTitle("\u{500d}\u{901f}")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
    }
}
