# Voice-Session Profile-Aware Pronunciation Realization

Last updated: March 31, 2026
Status: Final specification

## Overview

This specification defines how active pronunciation realization becomes aware of the selected English pronunciation profile.

## Backlink

Parent specification:

- [English Pronunciation Profiles and Rule Modularity](english-pronunciation-profiles-and-rule-modularity.md)

## Scope

This specification covers:

- profile-aware realization inputs
- active use of merged resources and enabled rule modules
- realization invalidation when the selected profile changes

This specification does not define engine-adapter behavior.

## Behavior

### Required Input Extension

Voice/session realization must additionally consume:

- selected English pronunciation profile id
- merged pronunciation resources for that profile
- enabled active/session-time rule modules for that profile

### Execution Rule

Voice/session realization must apply profile-aware decisions after document-time artifacts are loaded and before TTS artifacts are finalized.

### Invalidation Rule

Realization must be recomputed when the selected pronunciation profile changes, even if voice id remains the same.

### Traceability Rule

Realized pronunciation artifacts must preserve which profile id was active when the realization was produced.

## Constraints

- realization must not mutate cached document-time artifacts
- profile-aware realization must stay bounded to the active window and short look-ahead

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Active realization becomes profile-aware.
- Profile changes invalidate realized pronunciation output correctly.
- The final TTS artifact set can be traced back to the selected English profile.

