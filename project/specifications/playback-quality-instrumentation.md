# Playback Quality Instrumentation

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines the runtime metrics required to evaluate smoothness and long-form playback quality during development.

## Backlink

Parent architecture:

- [Playback Orchestration and Synthesis Boundaries](../architecture/playback-orchestration-and-synthesis-boundaries.md)

## Scope

This specification covers:

- debug and development metrics
- generation and playback timing events
- cache and boundary metrics

It does not define end-user analytics collection.

## Behavior

### Required Metrics

The first implementation round must expose:

- `firstAudioLatencyMs`
- `generationRealTimeFactor`
- `prefetchLeadTimeMs`
- `chunkCacheHit`
- `chunkRegenerated`
- `boundaryCorrectionApplied`
- `joinSilenceBeforeMs`
- `joinSilenceAfterMs`
- `playbackUnderrun`
- `positionMapConfidence`

### Event Scope

Metrics must be attributable to:

- `documentId`
- `sessionId`
- `chunkId`
- `voiceId`
- `engineId`

### Logging Rule

The first implementation round may log these metrics only in debug or developer-oriented builds.

The architecture does not require shipping external telemetry infrastructure for `v1`.

### Evaluation Support Rule

Instrumentation must make it possible to compare:

- paragraph playback versus sample playback
- cached versus regenerated playback
- pre-correction versus post-correction join silence

## Constraints

- instrumentation must not block playback
- instrumentation must not require network transport
- metric capture must remain usable on desktop and mobile targets

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Developers can inspect first-audio latency and cache-hit behavior per playback session.
- Boundary-policy changes can be evaluated with before/after join-silence metrics.
- Imported-document playback can be compared against bundled sample playback using the same metric set.
