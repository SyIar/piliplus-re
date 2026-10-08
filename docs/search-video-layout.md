# Search and video detail layout

This pass follows the design, resizability and accessibility guidance in
[SwiftUI Pro](https://github.com/twostraws/swiftui-agent-skill).
It keeps the existing iOS deployment target, Pika icons and ChunUI presentation
adapters. Player ownership, playback and navigation are unchanged.

## Search

- The tab accessory and keyboard accessory share one filter entry. Only the
  content type and a count of non-default filters appear in the compact bar.
- The panel exposes all content types, sorting and video durations. Unsupported
  sort/duration choices are hidden for non-video scopes.
- Selections are drafts until Apply. Cancel and a swipe dismissal do not change
  the current results. Apply starts at most one search for the last submitted
  keyword; unchanged selections do not cause another request.
- Compact result cards use a minimum height instead of a fixed height. At
  accessibility text sizes the cover and text stack vertically.

## Video detail

- An uploader row contains avatar, name and a compact Follow capsule with a
  44-point hit area.
- Like, Coin, Favorite and More have equal-width hit areas and captions.
  Favorite retains its long-press folder chooser.
- Share, Watch Later, Chapters and AI Summary are in More.
- More also contains the existing collection subscription, triple action and other
  tools. Triple still requires confirmation; no account operation runs merely
  from opening the panel.
- Primary actions remain in one row; captions can wrap at accessibility sizes.
- Comment toolbar buttons use the native toolbar surface without another glass
  button background.

## Mine and settings

Mine presents account information, three account statistics, four shortcuts and
a favorite-folder cover grid. Settings and secondary account tools have dedicated
entries. Unknown account values remain unavailable rather than appearing as zero.
Folder cards fetch missing cover metadata only when they become visible; the
account's Dynamic entry opens the uploader's dynamic section directly.

The directory follows the [upstream settings code](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/pages/setting/view.dart):
privacy, recommendations, audio/video, player, appearance, other, WebDAV,
account switching/logout, about. Directory and search use one category registry.
Existing setting keys and values are preserved. iOS-only diagnostics are in
Other > Advanced and diagnostics; Android/mpv-only controls are not copied.

WebDAV can be embedded in settings navigation without a second navigation stack
or a sheet-close button. Favorite and statistics refreshes ignore responses from
a previous account or superseded refresh.

## Review coverage

| Area | Checks |
| --- | --- |
| Shared styles | Glass ownership, form widths, semantic colors and presentation adapters |
| Home/search | Navigation, feed entry points, search accessory and result rows |
| Video/comments | Primary/secondary actions, follow hit area, bottom toolbar surfaces |
| Dynamic/live | Root controls, loading states, composition and player entry points |
| Uploader | Navigation and scrolling sections |
| Mine/settings | Dashboard, category navigation/search, preserved preference bindings |
| History/favorites/offline/messages | Shared lists, navigation and management controls |

At accessibility text sizes, dynamic categories use a menu, search discovery
uses one column, and live/offline action groups stack vertically to avoid narrow
button labels.

Source review does not replace live-account testing of every remote-data and
selection state. Representative production components have deterministic fixtures;
the coverage is not a claim that every screen was manually exercised.

## Verification

ContentLayoutUITests.swift exercises the production components through the
layoutSearch, layoutVideo, layoutMine, layoutSettings and layoutComments fixtures. It checks collapsed accessory bounds,
filter selection, equal reaction columns, minimum hit areas, tool access and
large-text layout, Mine shortcuts, settings navigation and comment toolbar actions.
MineDirectoryTests checks directory/search parity and account level decoding.
capture-preview.sh exports these test attachments and
light/dark iPhone and iPad previews.

The fixtures intentionally do not require live accounts or change account data.
They validate layout and navigation, not server-side interaction permissions or
playback quality. CI remains the authority for Swift compilation and tests.
Playback-startup investigation was withdrawn and is outside this UI change.
