# Emphasis Candidate Model

Last updated: April 1, 2026
Status: Final specification

## Overview

This specification defines how document-time emphasis candidates are represented before voice/session realization.

## Backlink

Parent specification:

- [Speech Annotation Set](speech-annotation-set.md)

## Scope

This specification covers:

- `emphasis_candidate` annotations
- emphasis span semantics
- emphasis confidence and intent rules

This specification does not define engine-specific emphasis expression.

## Behavior

### Annotation Kind

`emphasis_candidate` marks a word range that is likely to need stronger delivery than surrounding speech.

### Scope Rule

- an emphasis candidate must attach to one or more normalized words within one segment
- emphasis candidates must not cross segment boundaries
- the first implementation round uses the shared annotation envelope only and does not require a kind-specific payload

### Intent Rule

An emphasis candidate may represent:

- lexical stress worth preserving in delivery
- contrastive focus
- exclamatory force
- vocative or address-like emphasis

The annotation records emphasis intent, not exact acoustic behavior.

### Confidence Rule

- higher confidence indicates stronger evidence that the marked range should receive emphasis-sensitive realization
- importer-derived structural emphasis and user overrides may coexist with rule-based emphasis inference

### Realization Rule

- later realization may approximate or ignore an emphasis candidate if the active engine cannot express it directly
- the original emphasis candidate remains preserved in document-time annotations even when runtime realization is weak

## Constraints

- emphasis candidates must not inject engine-native markup into normalized text
- emphasis candidates must stay voice-agnostic at document time
- emphasis candidates must remain traceable to stable segment ids and word ranges

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The app can mark likely emphasis ranges without committing to engine-specific prosody controls.
- Emphasis intent remains available to realization, export, and future QA flows.
- The first implementation round can represent emphasis candidates with the shared annotation envelope alone.
