# Reader Diagnostics And Source Panels

## Architecture ownership

- [system overview](../architecture/system-overview.md)

Retained legacy contract. Final/refinement status is not implementation proof; current behavior is described in the architecture above. New work follows [AGENTS.md](../../AGENTS.md) and the active ACD/plan.

Status: final

## Overview

This specification defines the debug and document-information panels surfaced through Reader Options.

## Backlink

Historical specification lineage:

- [Reader Options And Secondary Settings UI](../archive/specification-ancestors/reader-options-and-secondary-settings-ui.md)

## Scope

This specification covers:

- interactive TTS input trace visibility
- live-tail presentation of trace output
- current document source-information presentation

## Behavior

The running app must provide a Reader Options section for speech-debug and source-information panels.

This surface should include:

- TTS input trace visibility for the current session when available
- a readable live-tail presentation of recent trace lines
- current document source information and attachment metadata when available

These panels are secondary inspection tools. They must not occupy permanent dominant space on the primary reading surface.

If no current trace exists yet, the surface should say so explicitly rather than appearing broken or empty.

If no document source metadata exists, the surface may fall back to a simple nonfatal placeholder.

## Constraints

- diagnostics presentation must remain consistent with the pronunciation and speech-QA specifications rather than inventing a second debug representation
- source information should stay informational and should not displace the reading surface

## Acceptance

- a user can inspect current TTS trace information from Reader Options in the running app
- a user can inspect current document source information from Reader Options in the running app
- these panels do not occupy persistent primary-surface space
