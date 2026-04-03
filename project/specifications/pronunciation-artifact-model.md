# Pronunciation Artifact Model

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines the durable document-time artifact model used to carry pronunciation intent in the internal speech representation.

## Backlink

Parent specification:

- [Pronunciation Planning and TTS Artifacts](pronunciation-planning-and-tts-artifacts.md)

## Scope

This specification covers:

- the base pronunciation artifact container
- per-artifact identity and range ownership
- artifact classes
- pronunciation representation payloads
- source and confidence requirements

This specification does not define how artifacts are inferred or realized for a specific voice.

## Behavior

### Required Container

`BasePronunciationArtifactSet` must contain:

- `String documentId`
- `String artifactVersion`
- `String normalizationVersion`
- `List<PronunciationArtifact> artifacts`

### Required Artifact Payload

Every `PronunciationArtifact` must contain:

- `String artifactId`
- `String segmentId`
- `int startWord`
- `int endWord`
- `String surfaceText`
- `String normalizedSurfaceText`
- `PronunciationArtifactClass artifactClass`
- `PronunciationArtifactSource source`
- `double confidence`
- `List<PronunciationRepresentation> representations`
- `List<String> diagnosticCodes`

`startWord` is inclusive. `endWord` is exclusive.

### Required Artifact Classes

The first implementation round must support:

- `resolved_lexical_case`
- `context_sensitive_case`
- `unresolved_case`

Meaning:

- `resolved_lexical_case`: document-time planning found a stable pronunciation candidate safe to cache with the document
- `context_sensitive_case`: document-time planning found a case that requires active voice/session realization before final pronunciation can be chosen
- `unresolved_case`: the planner could not produce a trustworthy pronunciation decision and wants the case tracked explicitly

### Required Representation Payload

Every `PronunciationRepresentation` must contain:

- `String representationId`
- `String representationType`
- `String representationValue`
- `String? accentFamily`
- `int priority`

The first implementation round must support these `representationType` values:

- `phoneme_string`
- `normalized_spoken_text`

### Source Rule

`PronunciationArtifactSource` must distinguish:

- `app_lexicon`
- `source_metadata`
- `rule_based_inference`
- `user_override`
- `fallback_unresolved`

### Confidence Rule

- `confidence` must be serialized as a double from `0.0` to `1.0`
- `resolved_lexical_case` artifacts must have at least one representation
- `unresolved_case` artifacts may have zero representations

### Range Rule

- every artifact must attach to one normalized `segmentId`
- one artifact may cover more than one word when the spoken unit is multi-word
- artifacts must remain traceable to `PositionMap` through `segmentId` and word range

## Constraints

- base pronunciation artifacts must be engine-agnostic
- inline engine markup must not be stored as the canonical base representation
- base pronunciation artifacts must not contain queue-local or audio-timing state

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The app can store pronunciation intent as a durable internal sidecar without mutating `SpeechDocument`.
- The model distinguishes stable lexical cases, context-sensitive cases, and unresolved cases.
- Stored representations remain usable across voice changes and engine translation passes.
