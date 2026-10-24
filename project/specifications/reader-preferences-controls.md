# Reader Preferences Controls

## Architecture ownership

- [system overview](../architecture/system-overview.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the active ACD/plan.

Status: final

## Overview

This specification defines the reading-preferences controls surfaced through the Reader Options secondary surface.

## Backlink

Historical specification lineage:

- [Reader Options And Secondary Settings UI](../archive/specification-ancestors/reader-options-and-secondary-settings-ui.md)

## Scope

This specification covers:

- current-voice speed adjustment
- reading-font selection
- reading-font scale adjustment
- placement of these controls in Reader Options rather than on the primary surface

## Behavior

The running app must expose reading-preferences controls through the Reader Options surface for:

- current voice speed
- reading font family
- reading font scale

These controls must affect the running app directly without requiring a restart.

Voice-speed adjustment should apply to the currently selected active voice rather than implying a global engine-wide rate.

Font family and font scale should affect the reading surface rather than being limited to secondary panels.

These controls must remain off the primary reading surface so they do not compete with transport and reading focus.

## Constraints

- preference controls must remain clearly secondary to the reading flow
- the app must not require a separate settings screen just to adjust these reading preferences
- the placement must stay consistent with the primary-surface complexity rule

## Acceptance

- a user can adjust voice speed, reading font, and reading font scale from the Reader Options surface in the running app
- these controls are not promoted to persistent primary-surface buttons or panels
- the resulting changes are visible or audible in the running app without restart
