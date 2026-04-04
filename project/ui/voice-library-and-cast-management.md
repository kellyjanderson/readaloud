# Voice Library and Cast Management

## Purpose

Define how voice selection, narrator/character assignment, and voice metadata should be surfaced without making the top-level interface visually busy.

## Primary-Surface Rule

The top-level surface should stay simple.

It may show:

- the active voice or narrator voice selector
- play and pause
- jump backward and forward
- the reading surface itself

It should not show:

- a large always-open voice management panel
- a flat wall of every available voice
- cast-management controls that only matter for dialogue-heavy documents

## Access To Advanced Voice Controls

Advanced voice controls should be accessed through the standard integrated iconographic affordance already defined for second-level UI complexity.

For voice-related domains, that affordance should open a dialog or sheet that can show:

- narrator voice
- detected character voices
- voice metadata
- override actions

## Voice Library Information Hierarchy

The voice-management surface should present voice information in this order:

1. name
2. locale
3. quality indicator when known
4. install state
5. short traits or description when requested

## Quality Metadata Surfacing

When the engine exposes voice quality metadata, the UI should surface it directly in the primary row for that voice.

Examples:

- grade badge such as `A-`
- short quality tier label
- explicit bundled or installed state

The user should not need to open a details popover just to see that one voice is materially higher quality than another.

## Description and Trait Surfacing

When a voice has optional traits or description metadata, the row should expose an `information` affordance:

- desktop: hover or click
- mobile: tap

The information affordance should reveal:

- short traits
- optional prose description
- optional supporting metadata such as training-duration class

If no description exists, the UI should still be allowed to show short traits only.

## Cast Management

When a document has a detected cast, the advanced voice dialog should group assignments by role:

- narrator
- characters
- unattributed dialogue fallback if needed

Each row should show:

- role or character name
- current assigned voice
- whether the assignment is automatic or user-overridden
- metadata/info affordance for the selected voice

## Override Semantics

Changing a narrator or character voice in this dialog is a user override.

The UI should make that state visible so the user can distinguish:

- automatic system cast
- explicit user choice

## Relationship To Other UI Docs

- [Primary Surface and Complexity Layering](primary-surface-and-complexity-layering.md)
- [Control State Semantics](control-state-semantics.md)
