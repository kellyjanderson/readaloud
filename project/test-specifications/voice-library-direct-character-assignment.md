# Voice Library Direct Character Assignment

Paired feature specification:

- [Voice Library Direct Character Assignment](../specifications/voice-library-direct-character-assignment.md)

## Manual Smoke Check

- Open Voice Management with character mode active.
- In the Voice Library, choose a character from a row-level selector and assign a discovered voice directly from that row.
- Confirm the corresponding character assignment at the top updates without requiring extra scrolling workflow.

## Automated Smoke Expectations

- widget coverage verifies that installed library rows in character mode show a row-level selector with default text `Assign` rather than `Use`
- widget coverage verifies that a character target can be selected from the row-level assignment control
- widget coverage verifies that selecting a character immediately calls the same override callback used by the top character assignment rows without a second confirmation button

## Automated Acceptance Expectations

- character mode preserves the top assignment cards for review while also enabling direct assignment from the library list
- narrator-only or cast-poor dialog states continue to use the simpler `Use` action
- row layout remains stable while the direct-assignment controls are present
