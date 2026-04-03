# In-App Audio Export Workflow

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines how a user exports spoken audio from the interactive app.

## Backlink

Parent specification:

- [Audio Export and Headless Execution](audio-export-and-headless-execution.md)

## Scope

This specification covers:

- export affordance in the app
- save-path choice behavior
- interaction with current voice and speed state
- export status and failure handling

## Behavior

### Export Source Rule

The exported audio must use:

- the currently loaded document
- the currently selected voice
- the current per-voice speed

### Availability Rule

Export is available only when:

- a document is loaded
- the document contains readable speech text
- an export-capable engine is active

### Save Path Rule

The interactive app must let the user choose an export destination when the platform supports a save-file flow.

If the platform-specific save-file flow is unavailable, the app may fall back to a deterministic local export path and must surface that path to the user.

### Interaction Rule

If playback is active or first-chunk buffering is in progress when export starts:

- the app may stop or pause active playback before export begins
- the app must not destroy cached chunk files
- the app must keep the document and reading position intact

### Status Rule

The app must surface:

- export start
- export success with output path
- export failure with a clear reason

### Completion Rule

Export completion does not automatically start playback and does not change the selected voice or speed.

## Constraints

- export must feel like a product action, not a hidden debug-only action
- interactive export must not require command-line usage
- export behavior must reuse the shared speech pipeline rather than a UI-only shortcut

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- a user can save spoken audio for the currently loaded document from the app
- the export uses the current voice and speed
- export preserves document state and surfaces a usable success path
