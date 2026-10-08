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

- An uploader row contains avatar, name and Follow.
- Like, Coin, Favorite and Share have equal-width hit areas and captions.
  Favorite retains its long-press folder chooser.
- Watch Later, Chapters, AI Summary and More form one secondary row.
- More contains the existing collection subscription, triple action and other
  tools. Triple still requires confirmation; no account operation runs merely
  from opening the panel.
- Reaction and shortcut grids use two columns at accessibility text sizes.
  No fixed card height or text shrinking is used to force these controls to fit.

## Verification

ContentLayoutUITests.swift exercises the production components through the
layoutSearch and layoutVideo fixtures. It checks collapsed accessory bounds,
filter selection, equal reaction columns, minimum hit areas, tool access and
large-text reflow. capture-preview.sh exports these test attachments and
light/dark iPhone and iPad previews.

The fixtures intentionally do not require live accounts or change account data.
They validate layout and navigation, not server-side interaction permissions or
playback quality. CI remains the authority for Swift compilation and tests.
