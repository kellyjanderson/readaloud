# Document-Time Pronunciation Planner

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines the document-time planner that produces cached pronunciation artifacts from normalized speech content.

## Backlink

Parent specification:

- [Pronunciation Planning and TTS Artifacts](pronunciation-planning-and-tts-artifacts.md)

## Scope

This specification covers:

- required planner inputs
- required planner outputs
- the initial inference strategy
- caching and invalidation rules

This specification does not define voice/session realization or engine translation.

## Behavior

### Required Input

`DocumentTimePronunciationPlannerInput` must contain:

- `SpeechDocument speechDocument`
- `BaseSpeechAnnotationSet baseAnnotations`
- `PositionMap positionMap`
- `String normalizationVersion`
- `Map<String, List<PronunciationRepresentation>> lexicalResources`
- `List<ImportDiagnostic> diagnostics`

### Required Output

The planner must emit one `BasePronunciationArtifactSet`.

### Processing Unit Rule

The planner must operate on normalized speech segments and adjacent local context.

The first implementation round must use:

- the current segment
- immediate neighboring segments in the same paragraph when needed for local context

The planner must not require whole-document engine calls or live runtime execution.

### Initial Detection Rules

The first implementation round must create artifacts for:

- explicit app-lexicon hits
- imported source metadata that already contains pronunciation information
- obvious context-sensitive cases flagged by rule-based heuristics
- unresolved cases the planner wants tracked explicitly

The planner must not globally rewrite all words through an ad hoc custom lexicon.

### Function-Word Rule

Function words such as `for` must not be finalized as stable document-time lexical resolutions unless the source itself explicitly provides a pronunciation directive.

Instead, these cases should be emitted as `context_sensitive_case` artifacts when the planner has evidence they require active realization.

### Unresolved Rule

If the planner cannot make a trustworthy document-time decision, it must emit an `unresolved_case` artifact rather than silently falling back and losing observability.

### Cache Rule

`BasePronunciationArtifactSet` is cacheable per:

- `documentId`
- `normalizationVersion`
- pronunciation-planner artifact version

Changing voice, rate, or playback position must not invalidate document-time pronunciation artifacts.

## Constraints

- the planner must not call the speech runtime
- the planner must not emit engine-specific markup into `SpeechDocument`
- the planner must remain lightweight enough for open-path execution or background continuation on older hardware

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The system can produce document-time pronunciation artifacts from normalized content without using live runtime synthesis paths.
- Stable lexical cases and context-sensitive cases are separated at document time.
- Uncertain cases remain visible as explicit unresolved artifacts.
