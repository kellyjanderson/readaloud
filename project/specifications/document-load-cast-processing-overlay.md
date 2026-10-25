# Document-Load Cast Processing Overlay

## Architecture ownership

- [system overview](../architecture/system-overview.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the GitHub design issue and slices.

Status: final

## Overview

This specification defines the visible processing state shown while the app performs document-load multi-voice analysis.

Issue anchor:

- GitHub issue `#19`

## Backlink

Historical specification lineage:

- [Primary Reader Surface UI](../archive/specification-ancestors/primary-reader-surface-ui.md)

## Scope

This specification covers:

- visible processing state while document-load cast analysis is running
- interaction suppression during that analysis
- progress presentation for multi-pass cast processing

## Behavior

When multi-voice document analysis is enabled and a document is loading, the app must expose a clear processing state rather than appearing idle.

That state must:

- grey out ordinary reading interaction
- visibly communicate that document analysis is in progress
- show progress for the document-load cast pipeline

The processing state may describe multiple internal passes such as:

- character and dialogue discovery
- cast metadata inference
- document-owned voice attribution materialization

The exact internal pass names may evolve, but the user must be able to tell that the document is still being prepared for multi-voice reading.

## Constraints

- the processing overlay must not look like a fatal error state
- it must remain clear that the app is still working
- normal reading controls should not appear fully ready while cast processing is incomplete

## Acceptance

- loading a document for multi-voice reading produces a visible processing overlay
- the UI no longer looks idle while cast analysis is still running
- the user can see progress rather than guessing whether the app is stuck
