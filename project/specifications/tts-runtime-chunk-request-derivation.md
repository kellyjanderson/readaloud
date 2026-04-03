# TTS Runtime Chunk Request Derivation

Last updated: March 31, 2026
Status: Final specification

## Overview

This specification defines how runtime chunk requests are derived from `TtsArtifactSet` and chunk-plan output.

## Backlink

Parent specification:

- [TTS Artifact Consumption Contract](tts-artifact-consumption-contract.md)

## Scope

This specification covers:

- required runtime-request inputs
- how chunk-plan chunks attach to `TtsArtifactSet` segments
- how prepared chunk payloads retain realized pronunciation artifacts

This specification does not define engine-specific translation behavior.

## Behavior

### Required Input

Runtime chunk derivation must consume:

- `ChunkPlan`
- `TtsArtifactSet`
- `SpeechDocument` when segment-range recovery is needed

### Segment Attachment Rule

Every `ChunkSpec` must carry the `TtsArtifactSegment` entries for the normalized segments it covers.

Runtime preparation must not look up those segment artifacts indirectly from controller state after chunk planning completes.

### Request Payload Rule

Every prepared runtime chunk payload must preserve:

- chunk identity
- normalized segment ids
- realized pronunciation artifacts for the chunk's covered segments
- speak text actually associated with those covered segments

### Export Parity Rule

Interactive playback and export/headless synthesis must derive runtime-ready chunk requests from the same chunk-artifact pairing logic.

## Constraints

- chunk derivation must not mutate the canonical `TtsArtifactSet`
- runtime chunk derivation must remain deterministic for the same chunk plan and artifact set

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Runtime chunk preparation uses pronunciation-aware artifacts already attached to planned chunks.
- Export and interactive playback share the same chunk-artifact derivation model.
- Pronunciation-aware runtime preparation no longer depends on reconstructing policy from only raw chunk text.
