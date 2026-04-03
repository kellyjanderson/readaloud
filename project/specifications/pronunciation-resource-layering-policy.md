# Pronunciation Resource Layering Policy

Last updated: March 31, 2026
Status: Final specification

## Overview

This specification defines how pronunciation resources are layered for an active English pronunciation profile.

## Backlink

Parent specification:

- [English Pronunciation Profiles and Rule Modularity](english-pronunciation-profiles-and-rule-modularity.md)

## Scope

This specification covers:

- resource layer ordering
- override precedence
- merge determinism

This specification does not define productive rule-module execution.

## Behavior

### Layer Order

The first implementation round must support this merge order:

1. global English resources
2. base variant resources
3. overlay-profile resources
4. imported source pronunciation metadata
5. user pronunciation overrides

### Override Rule

Higher layers override lower layers for the same lexical target.

### Determinism Rule

The merged result must be deterministic for the same selected profile and source inputs.

### Inspection Rule

The system must be able to expose which layer supplied the winning pronunciation resource for a lexical target.

## Constraints

- layering must not mutate the underlying source resource sets
- the merge policy must remain usable at document-time and voice/session-time

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The system has one deterministic merge order for pronunciation resources.
- Overlay and user layers can override lower layers cleanly.
- The winning layer remains inspectable for diagnostics and QA.

