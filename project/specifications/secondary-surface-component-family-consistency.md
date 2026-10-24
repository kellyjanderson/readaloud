# Secondary Surface Component Family Consistency

## Architecture ownership

- [system overview](../architecture/system-overview.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the active ACD/plan.

Status: final

## Overview

This specification defines the shared visual family for secondary surfaces such as dialogs, sheets, cards, chips, overlays, and related controls.

## Backlink

Historical specification lineage:

- [Visual Design System Adoption UI](../archive/specification-ancestors/visual-design-system-adoption-ui.md)

## Scope

This specification covers:

- dialogs
- bottom sheets
- assignment cards
- metadata sheets
- chips and badges
- temporary overlays

## Behavior

Secondary surfaces in the running app must feel like members of one design family instead of unrelated utility widgets.

For the current product phase, that family should share:

- common surface tokens
- common border treatment
- common radius language
- common elevation logic
- consistent quiet badge and chip styling

The voice-management dialog, metadata sheets, Reader Options sections, processing overlays, and contextual cards on the reading surface should all clearly belong to the same family.

## Constraints

- consistency must not erase hierarchy between primary reading and secondary surfaces
- badges and chips should stay informative, not loud
- overlays should communicate in-progress work without reading as fatal warnings

## Acceptance

- current dialogs, sheets, cards, chips, and overlays in the running app feel like one system
- secondary surfaces no longer present noticeably clashing visual moods
- current surfaces still preserve readable hierarchy and contrast
