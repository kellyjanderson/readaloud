# Secondary Surface Component Family Consistency

Status: final

## Overview

This specification defines the shared visual family for secondary surfaces such as dialogs, sheets, cards, chips, overlays, and related controls.

## Backlink

Parent specification:

- [Visual Design System Adoption UI](visual-design-system-adoption-ui.md)

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
