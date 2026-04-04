# Dialogue Span Detection

Status: final

## Overview

This specification defines how direct-speech spans are identified in normalized speech content.

## Backlink

Parent specification:

- [Dialogue Span and Speaker Attribution](dialogue-span-and-speaker-attribution.md)

## Scope

This specification covers:

- dialogue span identification
- span ids
- span-to-segment and span-to-word references
- confidence for span detection

## Behavior

The system must emit dialogue spans that:

- identify direct-speech or dialogue-like ranges in normalized speech content
- preserve normalized segment ids and word ranges for each detected span
- preserve confidence for each detected span
- distinguish detected dialogue from ordinary narration

Each detected span must have a stable id within one normalized document version.

A span may cover:

- one segment, or
- a contiguous multi-segment range

but it must remain traceable to exact normalized segment and word boundaries.

## Constraints

- detection is document-time work
- dialogue spans must remain engine-agnostic
- detection must recompute when normalized speech structure changes

## Acceptance

- the app can identify dialogue-like speech ranges before playback begins
- each detected range is traceable to normalized speech boundaries
- detected dialogue spans have stable ids within one normalized document version
