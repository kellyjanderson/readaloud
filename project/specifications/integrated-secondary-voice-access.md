# Integrated Secondary Voice Access

Status: final

## Overview

This specification defines how the primary surface exposes advanced voice and cast controls without cluttering the top-level UI.

## Backlink

Parent specification:

- [Primary Reader Surface UI](primary-reader-surface-ui.md)

## Scope

This specification covers:

- the integrated secondary affordance for advanced voice and cast controls
- discoverability without adding a competing top-level button family
- access behavior when a document has or does not have a detected cast

## Behavior

The running app must expose advanced voice and cast controls through a consistent integrated secondary affordance attached to the surfaced voice control or its control group.

That affordance should feel like:

- advanced options for the current voice domain
- not a separate independent primary action

Activating the affordance must open the advanced voice-management surface:

- narrator or default voice management when no cast is detected
- narrator and character cast management when a cast is detected

The affordance must remain visually secondary to the main reading controls while still being discoverable.

## Constraints

- advanced voice access must not require a dedicated competing top-level button
- the access path must remain consistent across desktop and mobile interaction modes
- the entry path must remain associated with the voice domain rather than appearing as unrelated global settings

## Acceptance

- the running app exposes advanced voice and cast controls through an integrated secondary affordance
- a user can discover and open advanced voice management without the primary surface becoming crowded
- the same access pattern works for narrator-only and cast-aware documents
