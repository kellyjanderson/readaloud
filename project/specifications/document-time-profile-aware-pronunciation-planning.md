# Document-Time Profile-Aware Pronunciation Planning

Last updated: March 31, 2026
Status: Final specification

## Overview

This specification defines how document-time pronunciation planning becomes aware of the selected English pronunciation profile.

## Backlink

Parent specification:

- [English Pronunciation Profiles and Rule Modularity](english-pronunciation-profiles-and-rule-modularity.md)

## Scope

This specification covers:

- profile-aware planner inputs
- document-time use of layered resources
- document-time rule-module execution

This specification does not define voice/session-time realization.

## Behavior

### Required Input Extension

The document-time planner must additionally consume:

- selected English pronunciation profile id
- merged pronunciation resources for that profile
- enabled document-time rule modules for that profile

### Execution Rule

Document-time planning must evaluate, in order:

1. merged pronunciation resources
2. enabled document-time rule modules
3. existing unresolved/documented fallback behavior

### Cache Rule

Document-time pronunciation artifact caching must include the selected profile id.

## Constraints

- document-time planning must stay engine-agnostic
- profile-aware document-time planning must remain lightweight enough for document-open or background continuation behavior

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Document-time pronunciation planning becomes profile-aware.
- Cached pronunciation artifacts are scoped to the active English profile.
- Resource-layer and rule-module use is explicit at document time.

