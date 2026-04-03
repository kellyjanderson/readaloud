# Voice-Session Pronunciation Realization

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines how cached pronunciation artifacts are realized for the active voice, rate, engine, and narration window.

## Backlink

Parent specification:

- [Pronunciation Planning and TTS Artifacts](pronunciation-planning-and-tts-artifacts.md)

## Scope

This specification covers:

- required realization input
- required realization output
- context-sensitive resolution rules
- realization invalidation rules

This specification does not define chunk audio generation.

## Behavior

### Required Input

`VoiceSessionPronunciationRealizationInput` must contain:

- `SpeechDocument speechDocument`
- `BasePronunciationArtifactSet basePronunciationArtifacts`
- `String startSegmentId`
- `String voiceId`
- `String engineId`
- `double rate`
- `NarrationState narrationState`

### Required Output

`VoiceSessionPronunciationRealization` must contain:

- `String realizationId`
- `String startSegmentId`
- `String endSegmentId`
- `String voiceId`
- `String engineId`
- `double rate`
- `List<RealizedPronunciationArtifact> artifacts`

Every `RealizedPronunciationArtifact` must contain:

- `String artifactId`
- `String segmentId`
- `int startWord`
- `int endWord`
- `String resolutionClass`
- `PronunciationRepresentation? selectedRepresentation`
- `String translationIntent`

### Resolution Classes

The first implementation round must support:

- `direct_resolved`
- `context_resolved`
- `deferred_to_engine`
- `unresolved`

### Context-Sensitive Rule

This layer is where `context_sensitive_case` artifacts are resolved for the active session.

It may use:

- nearby word context
- paragraph/dialogue context
- active voice and accent family
- current narration state

It must not require whole-document recomputation.

### Window Rule

Pronunciation realization must be limited to the active playback or export window and short look-ahead only.

### Invalidation Rule

The realization must be recomputed when:

- `voiceId` changes
- `engineId` changes
- `rate` changes
- the start segment moves outside the existing realization window
- the relevant narration continuity context becomes invalid

## Constraints

- realization must not mutate `BasePronunciationArtifactSet`
- realized pronunciation output must remain traceable to artifact ids and normalized segment/word ranges
- this layer must stay deterministic for the same input window and session context

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The system can resolve cached pronunciation artifacts for the active voice/session without whole-document recomputation.
- Context-sensitive cases are handled here instead of through blanket document-time lexical replacement.
- Realized pronunciation output is explicit and inspectable for the active window.
