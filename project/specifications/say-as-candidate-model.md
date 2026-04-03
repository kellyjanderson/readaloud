# Say-As Candidate Model

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines how document-time `say-as` intent is represented when text should be spoken according to a semantic reading class rather than naive orthography.

## Backlink

Parent specification:

- [Speech Annotation Set](speech-annotation-set.md)

## Scope

This specification covers:

- `say_as_candidate` intent
- the first-round `say-as` class vocabulary
- the relationship between `say_as_candidate` intent and pronunciation candidates that carry `say_as_class`

This specification does not define engine-specific SSML or markup syntax.

## Behavior

### Annotation Kind

`say_as_candidate` identifies a token or token range that should be spoken according to a semantic class.

### First-Round Class Vocabulary

The first implementation round must support:

- `letters`
- `cardinal`

### Scope Rule

- a `say-as` candidate may cover one or more normalized words within one segment
- the candidate must remain traceable to the original normalized token range

### Relationship Rule

The canonical class vocabulary for `say-as` behavior is shared across:

- `say_as_candidate` annotations
- pronunciation candidates whose `representationType` is `say_as_class`
- later TTS artifacts derived from those annotations

This means the system may carry `say-as` intent through either annotation form without changing the meaning of the class itself.

### Intent Rule

`say_as_candidate` is appropriate when:

- the planner knows the semantic reading class
- the app should preserve that class as internal speech intent
- the active engine may later realize the class directly or approximately

## Constraints

- `say-as` intent must remain engine-agnostic until adapter translation
- `say-as` classes must not be represented as raw engine markup in document-time annotations
- `say-as` intent must stay distinct from final phoneme output

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The app has a stable internal vocabulary for semantic reading classes such as letters and cardinals.
- `Say-as` intent can survive document-time planning, voice/session realization, and engine adaptation without being reduced to raw source text.
- The relationship between standalone `say-as` intent and pronunciation-candidate `say_as_class` payloads is explicit.
