# Voice Session Realization Envelope

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines the shared request and response envelope for active voice/session realization.

## Backlink

Parent specification:

- [Voice and Session Realization](voice-session-realization.md)

## Scope

This specification covers:

- `VoiceSessionRealizationInput`
- `VoiceSessionRealization`
- realization identity and invalidation behavior
- the relationship between realization output and `TtsArtifactSet`

This specification does not define pronunciation-resolution internals or the detailed realization of boundary and emphasis intent.

## Behavior

### Required Input

`VoiceSessionRealizationInput` must contain:

- `SpeechDocument speechDocument`
- `BaseSpeechAnnotationSet baseAnnotations`
- `String startSegmentId`
- `String voiceId`
- `String engineId`
- `double rate`
- `NarrationState narrationState`

The input may additionally carry:

- selected pronunciation profile
- merged pronunciation resources
- enabled active rule modules
- cached base pronunciation artifacts

Those additional fields remain valid extensions of the envelope as long as the core contract above is preserved.

### Required Output

`VoiceSessionRealization` must contain:

- `String realizationId`
- `String startSegmentId`
- `String endSegmentId`
- `String voiceId`
- `String engineId`
- `double rate`
- `String selectedProfileId`
- `TtsArtifactSet ttsArtifactSet`

It may additionally contain sidecar collections such as realized pronunciation artifacts when those are useful for debugging, export, or runtime derivation.

### Envelope Rule

- `TtsArtifactSet` is the canonical planner/runtime-facing payload produced by this layer
- realization-specific sidecars may exist, but they must remain traceable to the same segment ids and ranges as `TtsArtifactSet`
- chunk planning and runtime request derivation must consume the realization output without reconstructing active-session intent from raw text alone

### Identity Rule

`realizationId` must be deterministic for the same:

- document version
- start segment
- voice
- engine
- rate
- selected profile
- narration continuity context
- active realization window

### Invalidation Rule

The realization must be recomputed when:

- `voiceId` changes
- `rate` changes
- `engineId` changes
- the playback start point moves outside the existing realization window
- relevant `NarrationState` continuity becomes invalid

The realization must not be recomputed when only:

- display settings change
- unrelated documents are opened

## Constraints

- the realization envelope must stay independent from queue ownership and audio-generation state
- the envelope must remain serializable enough for logging, diagnostics, and export sidecars
- the envelope must not rewrite normalized segment ids

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The app has one stable request/response envelope for active-session realization.
- Chunk planning and runtime derivation can consume a canonical `TtsArtifactSet` produced by realization.
- Identity and invalidation rules for realization are explicit.
