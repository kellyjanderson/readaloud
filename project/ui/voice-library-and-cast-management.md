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

When multi-voice mode is enabled, the primary-surface voice entry should represent narrator choice plus access to cast management rather than exposing a competing wall of voice controls.

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

When multi-voice mode is on, the top-level entry should prefer a `Character Voices` entry path over the old single-voice picker so the surfaced control matches the current reading mode.

## Voice Library Information Hierarchy

The voice-management surface should present voice information in this order:

1. name
2. quality rank when known
3. gender when known
4. locale
5. preview action
6. install or assignment state
7. short description when available
8. short traits or description when requested

## Quality Metadata Surfacing

When the engine exposes voice quality metadata, the UI should surface it directly in the primary row for that voice.

Examples:

- grade badge such as `A-`
- short quality tier label
- explicit bundled or installed state

The user should not need to open a details popover just to see that one voice is materially higher quality than another.

When the app has gender metadata for a voice, that metadata should also be surfaced directly in the primary row rather than hidden behind a secondary details affordance.

## Preview Behavior

Each surfaced voice choice in the advanced voice-management domain should expose an explicit preview action.

That includes:

- voice-library rows
- narrator assignment rows
- character assignment rows

The preview action should play a short deterministic sample so the user can compare voices before assigning them.

Preview should be:

- immediate
- single-voice at a time
- clearly visible as playing, idle, or stopped

Preview should not require the user to commit a voice assignment first.

## Description and Trait Surfacing

When a voice has optional traits or description metadata, the row should expose an `information` affordance:

- desktop: hover or click
- mobile: tap

The information affordance should reveal:

- short traits
- optional prose description
- optional supporting metadata such as training-duration class

If no description exists, the UI should still be allowed to show short traits only.

If a short description exists, the first line or compact summary of that description should be visible directly in the row or assignment card rather than hidden entirely behind the information affordance.

## Cast Management

When a document has a detected cast, the advanced voice dialog should group assignments by role:

- narrator
- characters
- unattributed dialogue fallback if needed

Each row should show:

- role or character name
- current assigned voice
- preview action for the current assigned voice
- quality rank when known
- gender when known
- short description when available
- whether the assignment is automatic or user-overridden
- metadata/info affordance for the selected voice

When multi-voice mode is disabled, the app may continue to use the simpler single-voice path.

When multi-voice mode is enabled, narrator choice remains first-class, but the user-facing management surface should center on cast assignments rather than pretending the whole document is driven by one voice.

## Override Semantics

Changing a narrator or character voice in this dialog is a user override.

The UI should make that state visible so the user can distinguish:

- automatic system cast
- explicit user choice

## Relationship To Other UI Docs

- [Primary Surface and Complexity Layering](primary-surface-and-complexity-layering.md)
- [Control State Semantics](control-state-semantics.md)
