# Component System

## Purpose

This document defines the reusable UI component families for `Read Aloud`.

It sits between the design guide and narrower UI specifications.

The goal is to keep implementation moving through stable component patterns rather than inventing one-off widgets per screen.

## Component Families

### App Shell

The app shell owns:

- app bar
- platform-appropriate menu access
- bottom transport region
- global toast layer

The shell should present `Reader` as the only exposed workspace in the current product phase.

Platform rules:

- desktop shell: no in-app three-dots overflow menu
- desktop shell: native menu bar is the home for global commands, with File as the primary product-facing menu
- mobile shell: may expose a three-dots overflow menu for secondary or global commands
- do not duplicate the same desktop command family in both a native menu bar and an in-app overflow trigger

### Mobile Overflow Menu

The mobile overflow menu is the mobile-only secondary command collector.

It may contain:

- document actions that do not belong on the primary surface
- secondary settings or inspection surfaces
- export or advanced workflows

Rules:

- mobile only
- never the primary path to transport or reading itself
- should organize commands by domain rather than as one flat miscellaneous dump
- must not be mirrored by a redundant desktop overflow trigger

### Reader Surface

The reader surface is the main document canvas.

It should provide:

- readable long-form content
- spoken highlighting
- follow-along viewport behavior
- stable padding that protects the highlighted line from shell overlap

### Transport Capsule

The transport capsule is the primary playback control object.

It is one component with three segments:

- back
- play, pause, or processing
- forward

Rules:

- one shared background and border treatment
- center segment visually dominant
- side segments clearly tappable or clickable
- center processing state replaces play or pause only in the middle segment

### Voice Domain Control

The primary voice-domain control is the surfaced voice or cast entry on the main reader surface.

Rules:

- single-voice mode: shows the active voice
- multi-voice mode: shows the narrator or cast domain through `Character Voices`
- integrated secondary affordance opens advanced management

### Voice Preview Button

The preview button is a reusable voice-comparison control.

Rules:

- icon-led
- compact
- immediate
- one preview active at a time
- visible idle, playing, and stopping states
- if Reader playback is already active, preview pauses it automatically instead of asking the user to do extra setup work

Recommended label strategy:

- desktop may use icon plus tooltip
- mobile may use icon-only if touch target remains generous

### Voice Row

The voice row is the reusable library or picker row for one voice choice.

Required anatomy:

- name
- quality rank
- gender when known
- locale
- short description when available
- preview button
- information affordance
- assignment or install state

Layout rule:

- metadata and action slots should stay spatially stable across rows even when one metadata field is absent

### Assignment Card

The assignment card is the narrator or character voice row inside cast management.

Required anatomy:

- cast or role label
- automatic or override state
- selected voice
- visible metadata for the selected voice
- preview
- change or reset affordance

### Dialog

Dialogs are for focused secondary workflows.

Current primary dialog family:

- voice management

Rules:

- strong title
- readable body copy
- clear close affordance
- no washed-out field surfaces
- scrollable content area when needed

### Toast

Toasts are for non-blocking surfaced feedback.

Rules:

- float above layout
- float above dialogs and sheets
- never push the reader down
- concise copy
- explicit severity styling
- dismissible when they persist longer than a moment

### Processing Overlay

The processing overlay is for temporary blocking preparation work such as document-load cast analysis.

Rules:

- visible progress
- muted background interaction
- not styled like a fatal error

### Reader Options Section

A Reader Options section is a reusable grouped secondary-settings block.

Rules:

- clear section title
- related controls grouped together
- not visually heavier than the primary reading shell

### Recenter Control

The recenter control is a contextual follow-along affordance.

Rules:

- only visible when needed
- visually distinct but not dominant over the document
- should feel attached to follow-along, not to playback globally

## Workspace Components

### Reader Workspace

This workspace uses:

- App Shell
- Reader Surface
- Transport Capsule
- Voice Domain Control
- Toast
- Processing Overlay

### Future Authoring Tools

If authoring work eventually earns a surfaced workspace, it should be designed as its own component family rather than shipped as a stub.

## Implementation Flow

Implementation should move in this order:

1. product and project rules
2. [Brand Guide](brand-guide.md)
3. [Design Guide](design-guide.md)
4. component system
5. surface-specific UI definitions
6. UI specifications
7. concrete widgets and screens

## Relationship To Other UI Docs

- [Brand Guide](brand-guide.md)
- [Design Guide](design-guide.md)
- [UI System Overview](ui-system-overview.md)
