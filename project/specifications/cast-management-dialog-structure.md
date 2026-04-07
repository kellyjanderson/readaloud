# Cast Management Dialog Structure

Status: final

## Overview

This specification defines the structure of the advanced narrator/character voice-management dialog.

## Backlink

Parent specification:

- [Voice Library and Cast Management UI](voice-library-and-cast-management-ui.md)

## Scope

This specification covers:

- narrator and character grouping
- assignment row contents
- per-assignment voice preview
- selected-voice metadata visibility
- automatic-versus-override presentation

## Behavior

When a document has a detected cast, the advanced voice dialog should group assignments by role:

- narrator
- characters
- unattributed dialogue fallback when needed

Each assignment row should show:

- role or character name
- current assigned voice
- preview action for the current selected voice
- quality rank when known
- gender when known
- short description when available
- whether the assignment is automatic or user-overridden
- metadata/info affordance for the selected voice

Changing a narrator or character voice in this dialog creates a user override.

That override state must remain visible in the UI.

If no detected cast exists, the dialog may reduce to narrator/default voice management only.

## Constraints

- cast management must remain a secondary surface, not a permanently expanded top-level panel
- the UI must distinguish automatic and explicit user-selected assignment state
- the user must be able to preview a voice without committing to it first

## Acceptance

- narrator and character assignment rows have a defined structure
- narrator and character assignment rows expose voice preview
- selected-voice quality, gender, and short description are visible when available
- override state is visible
- the dialog works for both cast-rich and cast-poor documents
