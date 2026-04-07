# Primary Reader Control Set

Status: final

## Overview

This specification defines which controls remain visibly dominant on the primary reading surface.

## Backlink

Parent specification:

- [Primary Reader Surface UI](primary-reader-surface-ui.md)

## Scope

This specification covers:

- the persistent top-level reading controls
- reduction of top-level voice-management clutter
- removal of non-reading workflows from the primary surface

## Behavior

The primary reading surface should keep visible and dominant only the controls needed for normal reading flow:

- active voice selection
- play or pause
- jump backward
- jump forward
- the reading surface and current text context

Document identity should not consume a large banner area inside the reading surface.

When the app surfaces the current document name, it should do so outside the reading pane, such as in window or frame title chrome, rather than taking vertical space away from readable content.

The primary surface must not expose:

- a large always-open voice management panel
- a wall of voice options competing with the transport
- a persistent live-input button
- appearance-mode controls as primary reading controls
- a large document-title banner that pushes the reading surface downward or allows spoken highlighting to disappear beneath it

If a document has a detected cast, the primary surface should remain the same simplified reading surface rather than expanding into full cast-management UI.

## Constraints

- a user should be able to begin normal reading from the primary surface without opening secondary UI
- the active voice control must remain identifiable without forcing advanced voice-management UI onto the main surface

## Acceptance

- the running app visibly reduces the primary surface to reading-essential controls
- advanced workflows no longer occupy persistent top-level space on the reading surface
- a user can identify the active voice and transport controls without competing voice-management clutter
- document identity no longer occupies a large banner inside the reading surface
