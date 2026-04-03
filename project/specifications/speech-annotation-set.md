# Speech Annotation Set

Last updated: March 31, 2026
Status: Draft specification

## Overview

This specification defines the document-time, voice-agnostic speech annotation layer attached to `SpeechDocument`.

## Backlink

Parent architecture:

- [Speech Enrichment and Narration](../architecture/speech-enrichment-and-narration.md)

## Scope

This specification covers:

- `BaseSpeechAnnotationSet`
- annotation ownership
- annotation kinds
- confidence and provenance
- document-time caching expectations

This specification does not define voice-specific realization.

## Behavior

### Required Types

`BaseSpeechAnnotationSet` must contain:

- `String documentId`
- `String annotationVersion`
- `List<SpeechAnnotation> annotations`

Every `SpeechAnnotation` must contain:

- `String annotationId`
- `String segmentId`
- `SpeechAnnotationKind kind`
- `int startWord`
- `int endWord`
- `double confidence`
- `SpeechAnnotationSource source`

`SpeechAnnotationKind` for the first implementation round must support:

- `phrase_boundary`
- `pause_candidate`
- `emphasis_candidate`
- `pronunciation_candidate`
- `say_as_candidate`
- `discourse_role`

### Annotation Semantics

- annotations are attached to normalized speech segments
- word ranges are inclusive/exclusive
- annotations must never mutate source text
- multiple annotations may overlap if they represent different concerns

### Provenance Rule

`SpeechAnnotationSource` must distinguish:

- importer-structural inference
- rule-based linguistic inference
- explicit source metadata
- user override

### Confidence Rule

Confidence is normalized to `0.0` through `1.0`.

The first implementation round may use coarse buckets internally, but stored values must still serialize as normalized doubles.

### Cache Rule

`BaseSpeechAnnotationSet` is cacheable per normalized document version.

Changing voice or rate must not invalidate the base annotation set.

### Allowed Intent

The annotation set may represent speech intent that the current engine cannot fully honor directly.

Examples:

- stronger paragraph break intent than Kokoro can explicitly encode
- emphasis candidates that later realization may only approximate

## Constraints

- final phoneme strings do not belong in `BaseSpeechAnnotationSet`
- engine-specific audio timing does not belong in `BaseSpeechAnnotationSet`
- annotations must remain traceable to segment ids and word ranges
- annotation generation must be safe to run at document time or in document-time background continuation

## Refinement Status

This specification requires further refinement.

## Child Specifications

- [Speech Annotation Envelope Model](speech-annotation-envelope-model.md)
- [Pause and Break Taxonomy](pause-and-break-taxonomy.md)
- [Emphasis Candidate Model](emphasis-candidate-model.md)
- [Discourse Role Annotation Model](discourse-role-annotation-model.md)
- [Pronunciation Candidate Model](pronunciation-candidate-model.md)
- [Say-As Candidate Model](say-as-candidate-model.md)

## Acceptance

- The system can store reusable voice-agnostic speech hints per document.
- Annotation payloads remain stable across voice changes.
- The remaining speech-annotation work is represented by final leaf specifications.
- The model can represent phrase, pause, emphasis, pronunciation, `say-as`, and discourse hints without modifying `SpeechDocument`.
