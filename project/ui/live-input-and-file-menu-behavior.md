# Live Input And File Menu Behavior

Live file watching is useful, but it should not consume a full top-level control on the primary reading surface.

## Placement

Live file watching should be accessed from the File menu rather than a dedicated persistent primary-surface button.

It should also remain out of Reader Options so the workflow stays associated with document/file actions rather than general reading preferences.

## Behavioral Goal

Live mode should feel truly live.

When live mode is enabled:

- file changes should update the loaded document without reloading the app
- if playback is currently in the playing state, newly loaded changes should continue to play automatically
- playback should stop only when the user has explicitly placed the transport in the paused state

## Pause Semantics

Paused means paused by explicit user intent, not paused merely because the document updated.

When the transport is paused:

- live updates may still refresh the document
- audio should not resume automatically

When the transport is playing:

- live updates should continue the live-reading experience automatically after refresh

## Complexity Rule

This is an advanced workflow feature and should therefore follow the menu-placement rule rather than occupy constant space on the main interface.
