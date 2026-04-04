# Spoken Highlight Visual Presentation

Status: final

## Overview

This specification defines how the currently spoken text is visually highlighted on the reading surface.

## Backlink

Parent specification:

- [Follow-Along Reading Surface UI](follow-along-reading-surface-ui.md)

## Scope

This specification covers:

- visual priority of spoken highlight
- fallback highlight precision
- pause-state visual behavior

## Behavior

The spoken highlight should be visually obvious but not noisy.

The active spoken range should receive the strongest emphasis.

Highlight precision should follow this order:

1. current spoken word
2. current spoken phrase or segment
3. current visible block

When playback pauses, the spoken highlight remains visible on the last spoken range.

Surrounding context should remain readable and visually calm.

## Constraints

- highlight styling must remain legible in the supported appearance modes
- degraded mapping must still produce a meaningful visible highlight state

## Acceptance

- the reader surface has a defined spoken-highlight presentation
- fallback precision produces usable UI rather than disappearing silently
- pause behavior for the highlight is explicit
