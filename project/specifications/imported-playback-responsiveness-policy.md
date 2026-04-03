# Imported Playback Responsiveness Policy

Last updated: March 31, 2026
Status: Final specification

## Overview

This specification defines the responsiveness policy for imported-document playback, especially for ordinary document sizes where the user expects immediate interaction.

## Backlink

Parent specification:

- [Imported Document Playback](imported-document-playback.md)

## Scope

This specification covers:

- responsiveness priorities for imported playback
- the accepted architectural strategy for keeping first-audio latency low
- the explicit rejection of whole-document pre-generation as the normal path

This specification does not define instrumentation metrics themselves.

## Behavior

### Responsiveness Target

For imported documents under approximately `1500` words, the system must optimize for:

- first-audio latency
- interface responsiveness

rather than whole-document pre-generation.

### Accepted Strategy

The accepted strategy is:

- document-time structural normalization and base annotation inference
- windowed voice/session realization
- sentence-first chunk planning
- workerized synthesis

### Rejected Strategy

The normal imported-playback path must not require:

- whole-document voice-specific realization before audio starts
- whole-document synthesis before playback begins

## Constraints

- responsiveness policy must stay compatible with the normalized document architecture
- startup-speed optimization must not fall back to arbitrary character slicing or flat-string playback shortcuts
- responsiveness work must preserve correctness, not merely hide latency

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Imported playback has an explicit responsiveness policy instead of relying only on ad hoc implementation choices.
- The accepted strategy for fast startup is documented as a composed pipeline, not a vague performance goal.
- Whole-document pre-generation is explicitly excluded from the normal imported-playback path.
