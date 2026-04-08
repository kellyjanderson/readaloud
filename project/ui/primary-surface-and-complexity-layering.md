# Primary Surface And Complexity Layering

The primary reading surface should expose only the controls required for normal reading.

## Primary Interface Elements

The primary interface should center on:

- voice selection
- play or pause
- jump backward
- jump forward
- the selected or currently read text

These are the top-level elements that should remain visually dominant.

## Simplification Rule

The primary surface currently exposes too much voice and feature complexity.

The direction is to simplify that surface so it feels focused on reading rather than configuration.

## Voice Selection

Voice selection should remain accessible at top level, but the number of visibly competing options should be reduced.

The primary surface should prefer one clear active voice control over an expanded cluster of prominent voice-management UI.

When multi-voice mode is off, that control may be the ordinary single-voice selector.

When multi-voice mode is on, the top-level control should instead reflect narrator-plus-cast management:

- narrator remains the main selected voice
- the primary-surface entry becomes a `Character Voices` access path rather than a misleading whole-document voice picker
- the primary-surface entry should stay compact and action-oriented rather than expanding into a large summary card
- whole-document word count should not be promoted into the same top-level control row unless a later specification proves it is necessary for normal reading

## Secondary Access Pattern

When a domain is already represented on the primary surface, deeper options for that domain should be accessed through a consistent iconographic affordance integrated into the control itself or the control group.

This iconographic affordance is the standard path to secondary complexity.

It should feel like:

- advanced options for the control already in front of the user
- not a separate competing button family

## Document Identity Placement

Document identity should not consume a large banner area inside the reading surface.

The reading pane should be reserved for readable content and follow-along behavior rather than decorative title chrome.

For now, the preferred placement is outside the reading surface itself, such as:

- window or frame title chrome
- other non-content shell chrome when appropriate

When the current document is file-backed, the preferred visible label is the document file name.

The working window-title form should be:

- `Read Aloud - <document file name>`

The reading surface should therefore begin with readable document content rather than a large embedded title block that can obscure the top highlighted region.

## Menu Placement Rule

Features that add top-level complexity without being part of normal reading flow should move into menus by default.

Current example:

- live file watching belongs in the File menu rather than as a persistent primary-surface button

The same rule applies to authoring.

Authoring or studio workflows should not appear on the primary reading surface.

For now, they should not be surfaced in the shipped app at all.

### Platform Navigation Split

This menu-layering rule is platform-specific.

On macOS desktop:

- remove the in-app three-dots overflow menu from the Reader shell
- move the commands currently housed there into the native menu bar
- use the File menu as the primary product-facing home for those commands unless the platform reserves a command for the application menu

On mobile:

- preserve the three-dots overflow menu as the secondary command surface

Do not maintain a hybrid desktop shell where the same command family exists in both the native menu bar and an in-app overflow trigger.

## Secondary Settings Surface

General reading settings and inspection panels that do not belong in the File menu should prefer a shared secondary settings surface rather than each inventing their own primary-surface entry.

For the current app shell, that secondary surface is Reader Options.

Reader Options is the preferred home for:

- reading preferences such as font and scale
- appearance selection
- sleep timer and timing information
- debug trace and document-source inspection

## Document-Load Processing Feedback

When the app is performing document-load cast analysis for multi-voice reading, the UI should not appear idle.

The visible shell should enter a processing state that:

- greys out ordinary interaction
- communicates that multi-pass document analysis is underway
- can show progress rather than leaving the user to guess why playback or cast controls are not ready yet
