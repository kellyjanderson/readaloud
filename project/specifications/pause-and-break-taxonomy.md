# Pause and Break Taxonomy

Last updated: March 30, 2026
Status: Final specification

## Overview

This specification defines the reusable taxonomy for phrase, pause, and break annotations produced at document time.

## Backlink

Parent specification:

- [Speech Annotation Set](speech-annotation-set.md)

## Scope

This specification covers:

- break classes
- pause candidate semantics
- phrase-boundary semantics

## Behavior

### Required Break Classes

The first implementation round must support:

- `none`
- `weak`
- `sentence`
- `paragraph`
- `section`

### Phrase Boundary Annotation

`phrase_boundary` marks a likely sub-sentence phrasing boundary.

Rules:

- it may occur within a sentence
- it must map to a word boundary
- it must not imply a paragraph or section break by itself

### Pause Candidate Annotation

`pause_candidate` represents intended break strength at a word boundary or segment boundary.

Rules:

- `weak` is suitable for clause-like breaks
- `sentence` is suitable for normal sentence closure
- `paragraph` is suitable for paragraph transition
- `section` is suitable for headings or stronger structural transitions

### Alignment Rule

If both `phrase_boundary` and `pause_candidate` exist at the same boundary:

- `pause_candidate` defines the stronger playback-oriented interpretation
- `phrase_boundary` remains useful for chunk planning and future prosody modeling

## Constraints

- Break classes are engine-agnostic internal categories.
- Break classes do not encode exact silence durations.
- Annotation boundaries must align to normalized word boundaries.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The app has a consistent internal vocabulary for weak, sentence, paragraph, and section breaks.
- Document-time pause intent can be carried forward without depending on engine-specific APIs.
