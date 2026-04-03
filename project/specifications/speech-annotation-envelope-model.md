# Speech Annotation Envelope Model

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines the shared container and common field contract for document-time speech annotations.

## Backlink

Parent specification:

- [Speech Annotation Set](speech-annotation-set.md)

## Scope

This specification covers:

- `BaseSpeechAnnotationSet`
- common `SpeechAnnotation` fields
- annotation id and word-range semantics
- provenance and confidence rules
- cache and invalidation behavior

This specification does not define kind-specific payloads beyond the shared envelope.

## Behavior

### Required Set Type

`BaseSpeechAnnotationSet` must contain:

- `String documentId`
- `String annotationVersion`
- `List<SpeechAnnotation> annotations`

### Required Common Annotation Fields

Every `SpeechAnnotation` must contain:

- `String annotationId`
- `String segmentId`
- `SpeechAnnotationKind kind`
- `int startWord`
- `int endWord`
- `double confidence`
- `SpeechAnnotationSource source`

### Word-Range Rule

- `startWord` is inclusive
- `endWord` is exclusive
- zero-width boundary annotations are allowed when `startWord == endWord`
- non-boundary annotations must satisfy `startWord < endWord`

### Annotation Id Rule

- `annotationId` must be stable within one normalized document version
- ids do not need to survive normalization-version changes
- ids must be unique within one `BaseSpeechAnnotationSet`

### Provenance Rule

`SpeechAnnotationSource` must distinguish:

- `importer_structural_inference`
- `rule_based_linguistic_inference`
- `explicit_source_metadata`
- `user_override`

### Confidence Rule

- confidence is normalized to `0.0` through `1.0`
- stored values must serialize as numeric doubles
- `user_override` annotations should use `1.0` unless a later spec explicitly says otherwise

### Overlap Rule

- multiple annotations may overlap when they describe different concerns
- competing annotations of the same `kind` may overlap only when later realization policy is expected to resolve them explicitly

### Cache Rule

`BaseSpeechAnnotationSet` is cacheable per normalized document version.

It must invalidate when:

- normalized segment ids change
- annotation inference logic version changes

It must not invalidate when only:

- voice changes
- rate changes
- display settings change

## Constraints

- common annotation fields must stay engine-agnostic
- the annotation envelope must remain serializable
- the shared envelope must not contain raw audio timing or engine-native payloads

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The app has one stable shared contract for all document-time speech annotations.
- Annotation ids, segment references, and word ranges are defined without depending on kind-specific payloads.
- Provenance, confidence, and cache semantics are explicit and reusable across annotation kinds.
