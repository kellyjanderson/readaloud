# Follow-Along User Scroll Interaction

Status: final

## Overview

This specification defines how auto-follow interacts with user-controlled scrolling on the reading surface.

## Backlink

Parent specification:

- [Follow-Along Reading Surface UI](follow-along-reading-surface-ui.md)

## Scope

This specification covers:

- manual-scroll yield behavior
- snapback avoidance
- re-centering affordance

## Behavior

If the user manually scrolls while playback is running, the interface should temporarily yield control of the viewport.

It must not snap back immediately.

The UI may offer a simple way to re-center on the active spoken range.

When playback resumes from a paused state, follow behavior resumes according to the underlying reading-focus policy.

## Constraints

- user scroll behavior must not fight the user
- any re-centering affordance must remain simple and subordinate to the reading surface

## Acceptance

- user scrolling no longer causes immediate snapback
- the UI has a defined re-centering behavior
- follow-along interaction remains stable during active playback
