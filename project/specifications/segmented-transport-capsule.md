# Segmented Transport Capsule

Status: final

## Overview

This specification defines the unified transport object for normal reading playback.

## Backlink

Parent specification:

- [Primary Reader Surface UI](primary-reader-surface-ui.md)

## Scope

This specification covers:

- one shared transport container
- three independent hit targets
- visual hierarchy between back, play or pause or processing, and forward
- separator and sizing rules

## Behavior

The running app must present playback transport as one segmented capsule rather than three visually unrelated controls.

That capsule must contain:

- left segment: jump backward
- center segment: play, pause, or processing
- right segment: jump forward

The center segment is the primary action and should be visually wider than the side segments.

The overall control should be modestly taller than the prior button set so the transport feels intentional and easier to target.

Thin separators may be used between the center and side segments, but they should stay quiet rather than becoming decorative stripes.

Processing state belongs only in the center segment and must not replace the back or forward affordances.

The capsule is one visual object, but it must not behave like one literal single hit target.

## Constraints

- the three transport actions must remain independently tappable or clickable
- the capsule must remain calmer than three disconnected buttons without reducing clarity
- transport styling must use the semantic theme system rather than one-off literal colors

## Acceptance

- the running app shows one segmented transport capsule instead of three unrelated transport buttons
- back, play or pause or processing, and forward remain independent targets
- the center segment is visually dominant
- processing state appears only in the center segment
