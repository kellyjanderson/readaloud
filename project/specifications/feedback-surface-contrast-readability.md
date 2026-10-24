# Feedback Surface Contrast Readability

## Architecture ownership

- [system overview](../architecture/system-overview.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the active ACD/plan.

Status: final

## Overview

This specification defines the minimum contrast requirements for surfaced in-app feedback while the broader feedback UX remains under later redesign.

Issue anchor:

- GitHub issue `#24`

## Backlink

Historical specification lineage:

- [Primary Reader Surface UI](../archive/specification-ancestors/primary-reader-surface-ui.md)

## Scope

This specification covers:

- in-app surfaced status readability
- foreground-to-surface contrast for feedback banners or temporary feedback surfaces
- close affordance readability

## Behavior

Any surfaced in-app feedback shown during ordinary reading must remain readable in both light and dark appearance modes.

The quick contrast-remediation pass may preserve the current placement and general structure of the feedback surface, but its colors must no longer produce low-contrast text or icons.

Foreground text, supporting iconography, and dismiss affordances must remain legible against the chosen feedback background.

## Constraints

- this specification addresses readability only, not the later layout and hierarchy redesign
- the later transient-feedback redesign remains tracked separately
- the quick pass must improve testability without pretending the larger UX issue is solved

## Acceptance

- surfaced feedback text is readable in light mode
- surfaced feedback text is readable in dark mode
- icons and dismiss affordances remain readable against the feedback surface
- the running app no longer presents unreadable feedback while broader feedback-surface redesign remains pending
