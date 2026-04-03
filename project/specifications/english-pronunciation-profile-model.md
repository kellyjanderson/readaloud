# English Pronunciation Profile Model

Last updated: March 31, 2026
Status: Final specification

## Overview

This specification defines the data model for English pronunciation profiles.

## Backlink

Parent specification:

- [English Pronunciation Profiles and Rule Modularity](english-pronunciation-profiles-and-rule-modularity.md)

## Scope

This specification covers:

- required profile fields
- profile inheritance metadata
- profile classification

This specification does not define selection logic or resource merge behavior.

## Behavior

### Required Fields

An English pronunciation profile model must contain at least:

- `String profileId`
- `String localeTag`
- `String accentFamily`
- `String englishVariantFamily`
- `String? parentProfileId`
- `bool isOverlayProfile`
- `List<String> resourceLayerIds`
- `List<String> enabledRuleModuleIds`

### Base Profile Rule

Core profiles such as `en-us-core`, `en-gb-core`, and `en-au-core` must have:

- `isOverlayProfile == false`
- `parentProfileId == null`

### Overlay Profile Rule

Accent-overlay profiles must have:

- `isOverlayProfile == true`
- a non-null `parentProfileId`

### Identity Rule

`profileId` must be stable enough to appear in:

- cache keys
- diagnostics
- export sidecars
- future QA surfaces

## Constraints

- the model must not embed engine-native markup
- the model must be usable by planner code without requiring runtime engine access

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- The system has one stable data model for English pronunciation profiles.
- Base and overlay profiles are distinguishable without extra inference.
- Profile identity is stable enough for caching and diagnostics.

