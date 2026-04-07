# Voice Management Dialog Contrast And Readability

Status: final

## Overview

This specification defines the minimum contrast and readability requirements for the narrator and character voice-management dialog.

Issue anchor:

- GitHub issue `#27`

## Backlink

Parent specification:

- [Voice Library and Cast Management UI](voice-library-and-cast-management-ui.md)

## Scope

This specification covers:

- dialog-surface contrast
- narrator and character card readability
- assigned-voice field readability
- badge, metadata, and section-header legibility

## Behavior

The voice-management dialog must remain comfortably readable in both light and dark appearance modes.

The dialog background, interior cards, form fields, badges, labels, and selected voice values must use contrast that makes the surface usable before any interaction.

In dark mode:

- the dialog may remain dark, but text and field chrome must be clearly legible against the selected surfaces
- light card interiors must not be paired with near-white text

In light mode:

- the dialog may remain light, but labels and selected values must remain clearly darker than the surface

Automatic or override badges, quality badges, locale text, helper text, and close affordances must all remain readable without hover or focus.

## Constraints

- the quick contrast-remediation pass may improve colors without redesigning the structure of the dialog
- readability takes priority over decorative palette choices
- the dialog must be testable without requiring the later broader UI overhaul

## Acceptance

- narrator and character assignment cards are readable in light and dark modes
- assigned voice selectors and selected values are readable in light and dark modes
- quality badges, override badges, locale text, and helper text are readable
- the running dialog is usable enough for continued functional testing
