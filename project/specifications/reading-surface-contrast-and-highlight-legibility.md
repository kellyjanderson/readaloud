# Reading Surface Contrast And Highlight Legibility

Status: final

## Overview

This specification defines the required contrast and highlight behavior for the reading surface across supported appearance modes.

Issue anchor:

- GitHub issue `#16`

## Backlink

Parent specification:

- [Follow-Along Reading Surface UI](follow-along-reading-surface-ui.md)

## Scope

This specification covers:

- baseline text-to-surface contrast on the reading pane
- dark-mode reading-surface colors
- highlight styling that preserves text readability
- compatibility with light, dark, and follow-system modes

## Behavior

The reading surface must remain comfortably readable in every supported appearance mode.

In dark mode:

- the reading pane should use a very dark gray surface rather than a bright paper-like panel
- default reading text should use a clearly lighter foreground with strong contrast against that surface

In light mode:

- the reading pane may remain light, but body text must still preserve strong readable contrast

The spoken highlight must not wash out the underlying text.

When the active spoken range is highlighted:

- the highlight color may change the background of the active range
- the text color within that active range must remain clearly legible against the highlighted background
- non-active surrounding text must remain readable instead of fading into near invisibility

Follow-system mode must preserve those same readability rules when the operating system appearance changes.

## Constraints

- the reading surface must not rely on low-contrast light-on-light or dark-on-dark combinations
- spoken-highlight styling must preserve readability before decorative emphasis
- the running app must make the improved contrast directly observable without requiring diagnostics

## Acceptance

- dark mode shows a very dark gray reading surface with clearly lighter readable text
- light mode shows a readable light reading surface with adequately dark text
- the spoken highlight remains visible without making the spoken text illegible
- surrounding non-highlighted text remains readable while playback is active
- the running app remains legible when follow-system switches between light and dark modes
