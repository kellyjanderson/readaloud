# Pronunciation Candidate Model

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines how reusable pronunciation candidates are represented at document time.

## Backlink

Parent specification:

- [Speech Annotation Set](speech-annotation-set.md)

## Scope

This specification covers:

- pronunciation candidate annotations
- candidate payload shape
- accent applicability

## Behavior

### Required Pronunciation Candidate Payload

A `pronunciation_candidate` annotation must include:

- `String surfaceText`
- `String normalizedSurfaceText`
- `String representationType`
- `String representationValue`
- `String? accentFamily`
- `int priorityHint`

### Representation Types

The first implementation round must support:

- `phoneme_string`
- `say_as_class`
- `normalized_spoken_text`

### Accent Rule

- `accentFamily` may be null when the candidate is accent-neutral
- when present, `accentFamily` should use stable values such as `en-us` or `en-gb`

### Scope Rule

- pronunciation candidates must attach to a normalized word span
- one annotation may cover more than one word when the spoken unit is multi-word

## Constraints

- Document-time pronunciation candidates are reusable hints, not final engine output.
- Candidates must remain engine-agnostic enough to survive engine replacement where possible.
- Final selected pronunciation belongs to voice/session realization.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The app can store reusable pronunciation candidates without committing to a final voice-specific pronunciation choice.
- Candidates can distinguish phoneme-based, class-based, and normalized-text representations.
