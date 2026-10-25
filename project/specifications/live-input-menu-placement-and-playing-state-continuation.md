# Live Input Menu Placement And Playing-State Continuation

## Architecture ownership

- [system overview](../architecture/system-overview.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the GitHub design issue and slices.

Status: final

## Overview

This specification defines where live input is accessed in the running app and how playback should behave when the watched file changes.

## Backlink

Historical specification lineage:

- [Live Input And File Menu UI](../archive/specification-ancestors/live-input-and-file-menu-ui.md)

## Scope

This specification covers:

- File-menu placement of live input controls
- continuation behavior when live input refreshes during playback
- paused-state semantics for live updates

## Behavior

The running app must expose live input through the File menu rather than as a persistent top-level button on the primary reading surface.

When live input is enabled and the watched file changes:

- the loaded document should refresh inside the running app without restarting the app
- if the transport is in the playing state, the live-reading experience should continue automatically after the refresh
- if the transport is paused by explicit user intent, audio must remain paused after the refresh

Paused means paused because the user chose pause, not merely because the document refreshed.

The running app may surface live-input status, but that status should not become a competing persistent primary-surface control.

## Constraints

- menu placement must remain consistent with the primary-surface complexity rule
- continuation behavior must reuse the same document-refresh path defined by the continuity specification rather than inventing a separate live parser

## Acceptance

- a user can access live input from the File menu in the running app
- when playback is active, file changes continue the live-reading experience automatically after refresh
- when playback is paused explicitly, file changes do not resume playback automatically
- live input no longer occupies a persistent primary-surface button
