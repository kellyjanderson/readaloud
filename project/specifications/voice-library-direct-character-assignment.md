# Voice Library Direct Character Assignment

Status: final

## Overview

This specification defines direct character-assignment workflow from the voice-library rows inside the Voice Management dialog when character mode is active.

Issue anchor:

- GitHub issue `#44`

## Backlink

Parent specification:

- [Voice Library and Cast Management UI](voice-library-and-cast-management-ui.md)

## Scope

This specification covers:

- installed-voice primary action behavior in character mode
- per-row character-target selection from the library list
- direct assignment of a discovered voice to a character without scrolling back to the top assignment cards

## Behavior

When character mode is active and the document has detected character cast entries, installed voice rows in the Voice Library should prefer a direct assignment workflow over the older narrator-centric `Use` action.

In that state:

- each installed voice row should expose a compact target selector whose default visible text reads `Assign`
- choosing a character from that selector should immediately create the same user override as assigning that voice from the character assignment rows above
- the row-level assignment workflow should not require a second confirmation button press

The character assignment rows at the top of the dialog should remain in place.

Those top rows and the voice-library assignment workflow serve different needs:

- the top rows support efficient per-character review and editing
- the library rows support efficient voice discovery and immediate assignment to a chosen character

When no detected character cast exists, the library may fall back to the simpler narrator-centric `Use` action.

## Constraints

- the library assignment workflow must not force the user to scroll back to the top of the dialog just to complete an obvious assignment
- the direct-assignment controls must preserve stable row layout
- the library action must remain clearly distinct from installation state and preview state

## Acceptance

- in character mode, installed voice rows no longer use a narrator-centric `Use` label as their primary action
- the user can choose a character target directly from the voice-library row
- assigning from the library creates the same override result as assigning from the character rows above
- narrator-only or cast-poor documents may still use the simpler `Use` behavior
