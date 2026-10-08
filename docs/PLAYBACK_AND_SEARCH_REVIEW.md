# Playback and search review

## Confirmed crash

All four device reports supplied on 2026-10-08 (builds 92 and 95) share this stack:

1. `PlayerPerformanceSessionPersistenceWriter.persist(_:forKey:)` writes defaults on a cooperative executor.
2. `UserDefaults.didChangeNotification` is delivered synchronously on that executor.
3. The `PiliPlaybackPreferences` Combine sink enters a MainActor-isolated closure.
4. `_dispatch_assert_queue_fail` terminates the process with `EXC_BREAKPOINT`.

Scheduling onto the main run loop must happen **before** the sink. Creating a MainActor task inside an already isolated sink is too late. A regression test posts the notification from a detached task and verifies that the changed preference is delivered on the main thread. The original device logs are kept outside the repository.

## Background playback

The app already declared the background audio capability, but its lifecycle explicitly paused recorded video, disabled Now Playing metadata and rejected playback while inactive. Background transitions now preserve the item and playback intent. AVPlayer uses `continuesIfPossible`; user pauses, audio interruptions, headphone removal and navigation retain their respective semantics. Paused items remain controllable through system Now Playing. Ended/stopped items clear their system surfaces.

A WidgetKit extension displays an optional playback Live Activity. It uses ActivityKit authorization, serializes updates, throttles progress, and ends the activity when the active playback session ends. Standard system Now Playing owns lock-screen and Control Center playback commands. No repeating local notifications are posted. Device verification remains necessary for background audio, lock-screen controls and Live Activity presentation after IPA resigning.

## Layout scope

The original Flutter structure was checked in:

- https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/pages/search_result/view.dart
- https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/plugin/pl_player/widgets/bottom_control.dart

Search now defaults to videos with separate category tabs, a single history heading/clear row, and native-search text synchronization that cannot replay stale activation callbacks. Switching categories clears the previous result list while the selected request loads.

Portrait controls place navigation and secondary tools above the video, then progress above a single playback/time/subtitles/rate/fullscreen row. Landscape uses the same bottom hierarchy, with title/navigation above and lock/capture at the sides. Queue, timer, sharing, reactions and skip actions are grouped in More. The existing Liquid Glass theme remains. Playback icons use full-size Pika glyphs and common 44-point interaction targets.

The existing profile, settings-directory, detail-action and comment-toolbar regression fixtures remain part of CI. This is not a claim of pixel parity for every account-dependent page, every dialog, or unsupported upstream features. Live controls, real media transitions, rotation, large text and system surfaces require their respective simulator/device checks.

## Platform references

- https://developer.apple.com/documentation/avfoundation/avplayeraudiovisualbackgroundplaybackpolicy
- https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter
- https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- https://github.com/twostraws/swiftui-agent-skill/tree/main/swiftui-pro
