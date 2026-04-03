# English Pronunciation Profile Selection Policy

Last updated: March 31, 2026
Status: Final specification

## Overview

This specification defines how the active English pronunciation profile is selected.

## Backlink

Parent specification:

- [English Pronunciation Profiles and Rule Modularity](english-pronunciation-profiles-and-rule-modularity.md)

## Scope

This specification covers:

- required selection inputs
- fallback order
- deterministic selection behavior

This specification does not define how resources are merged after selection.

## Behavior

### Required Inputs

Profile selection must be able to consume:

- `voiceId`
- `engineId`
- available locale or accent metadata associated with the voice
- an optional user-selected pronunciation preference

### Fallback Order

The first implementation round must use this fallback order:

1. explicit user-selected pronunciation profile
2. exact voice-mapped English profile
3. locale-family default profile
4. `en-us-core`

### Determinism Rule

The same selection inputs must always produce the same profile id.

### Unsupported Profile Rule

If a requested profile is unavailable, the selector must choose the next valid fallback rather than failing silently.

## Constraints

- profile selection must not depend on runtime synthesis success
- profile selection must remain usable during document-time planning

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The system has one deterministic policy for selecting the active English pronunciation profile.
- User preference, voice mapping, and fallback order are explicit.
- Planner and realization code can ask for the same selected profile and get the same answer.

