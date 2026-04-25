---
name: brand-and-component-rules
description: Apply Read Aloud-specific brand voice, naming, typography, color, navigation, and component behavior rules while preserving the shared UI invariants.
---

# Brand And Component Rules

This Skill distills Read Aloud brand, design, and component decisions into direct operating rules.

## Shared Invariants Still Apply

The shared UI invariants remain mandatory.

This Skill refines look, voice, and product behavior without overriding structural UI rules.

## Product Voice

User-facing copy should be:

* calm
* plainspoken
* specific
* low on technical jargon
* reassuring without sounding gushy

## Naming Rules

Use these terms consistently:

* product name: `Read Aloud`
* primary workspace: `Reader`
* secondary settings surface: `Reader Options`
* multi-voice entry: `Character Voices`

Default to `document` in user-facing copy unless file-backed behavior specifically matters.

## Typography

Use:

* `Source Sans 3` for chrome, menus, buttons, and controls
* `Source Serif 4` for reading content
* `IBM Plex Mono` for technical or debug surfaces

## Color Direction

Use the editorial-warm palette defined by the project guides.

Accessibility wins over branding.

## Workspace Rule

`Reader` is the default and only exposed workspace in the current phase.

Do not leak authoring controls or placeholder authoring surfaces into the main Reader workspace.

## Component Rules

Protect these component behaviors:

* segmented transport capsule with three hit targets
* curated voice-management rows with preview support
* preview that pauses ordinary Reader playback automatically when appropriate
* toast, overlay, and modal feedback used for distinct purposes
* document-first reading surface
* stable scan positions in voice-library rows
