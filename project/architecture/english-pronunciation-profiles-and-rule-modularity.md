# English Pronunciation Profiles and Rule Modularity

Last updated: April 3, 2026
Status: Active architecture

## Purpose

This document defines how `Read Aloud` supports modular pronunciation behavior for multiple English variants and accented-English profiles without hard-coding one global rule set.

## Overview

The system must not treat English pronunciation behavior as one fixed policy.

`Read Aloud` needs a modular pronunciation architecture that can support:

- American English
- British English
- Australian English
- future region-specific English variants
- future accented-English overlays such as German English or Spanish English

This architecture exists because:

- pronunciation rules are not identical across English variants
- lexical resources differ by variant
- productive phonology rules may stay structurally similar while surface preferences differ
- the app must eventually support multiple voices and accent families without duplicating the whole pronunciation pipeline

## Components

### English Pronunciation Profile

This is the selected pronunciation profile for the active planning or realization pass.

Responsibilities:

- identify the active English variant or accented-English overlay
- expose stable profile ids and inheritance relationships
- define the accent family and locale family used by planning and realization
- declare which pronunciation resources and rule modules are active

Examples:

- `en-us-core`
- `en-gb-core`
- `en-au-core`
- future overlay profiles such as `en-us-german-accented`

### Profile Registry

This is the app-owned set of supported pronunciation profiles.

Responsibilities:

- provide discoverable profile metadata
- provide stable parent/child profile relationships
- allow fallback when the requested profile is unavailable
- keep profile selection decoupled from any single engine

### Pronunciation Resource Layers

These are the layered resources used by pronunciation planning and realization.

Responsibilities:

- separate global English resources from variant-specific resources
- allow profile-specific lexical additions and overrides
- allow future user dictionaries and imported source metadata to layer above profile defaults
- preserve deterministic merge order

Examples:

- global English resources
- variant lexical resources such as `en-us` or `en-gb`
- profile-specific overlays
- future user overrides

### Pronunciation Rule Modules

These are composable rule units that operate on normalized speech content.

Responsibilities:

- handle productive pronunciation behaviors that should not be encoded only as lexicon entries
- remain modular so different English profiles can enable, disable, or tune them
- operate at document-time or voice/session-time depending on the rule

Examples:

- English `s`-allomorph realization
- future reduced-form function-word handling
- future dialect-sensitive lexical stress adjustments

### Profile Selection

This is the policy that chooses which pronunciation profile is active.

Responsibilities:

- map the active voice, locale, and engine settings to a pronunciation profile
- provide deterministic fallback when no exact profile exists
- allow a future user-selected pronunciation preference to override defaults

### Document-Time Profile-Aware Planning

This is the document-time pass that uses the selected English profile.

Responsibilities:

- apply profile-specific lexical and rule-module behavior that is safe to cache with the document
- produce profile-scoped base pronunciation artifacts
- keep planner-owned pronunciation intent separate from engine behavior

### Voice/Session Profile-Aware Realization

This is the active realization pass that uses the selected English profile and session context.

Responsibilities:

- adapt cached pronunciation artifacts for the current voice/accent/rate
- apply active rule modules that depend on nearby context or active profile behavior
- produce the final profile-aware TTS artifact set consumed by chunk planning and engine translation

## Relationships

- profile selection chooses an `EnglishPronunciationProfile`
- the profile points to pronunciation resource layers and enabled rule modules
- document-time planning uses the selected profile to build cacheable pronunciation artifacts
- voice/session realization uses the same selected profile plus session context to produce realized TTS artifacts
- engine translation consumes profile-aware TTS artifacts but does not own profile selection

## Data Flow

```text
voice + locale + engine + optional user preference
  -> profile selection
  -> EnglishPronunciationProfile
  -> resource layering + enabled rule modules
  -> document-time pronunciation planning
  -> BasePronunciationArtifactSet
  -> voice/session realization
  -> TTS Artifact Set
  -> engine translation
```

## Cross-Domain Solutions

### 1. English pronunciation must be profile-based, not globally hard-coded

The system must choose a pronunciation profile rather than relying on one universal English rule set.

Reason:

- variant-specific behavior is real
- voices and future engines may prefer different accent families
- one global policy becomes brittle as soon as multiple English variants are supported

### 2. Productive pronunciation behavior must be modular

The system must model productive pronunciation behavior as rule modules instead of only lexicon entries.

Reason:

- plural, possessive, and similar morphological behavior is productive
- lexicons are useful, but not sufficient, for productive phonology
- rule modules can be shared across profiles and tuned where variants differ

### 3. Resource layering and rule modules are separate concerns

The architecture must not collapse lexicon resources and productive rules into one mechanism.

Reason:

- lexical resources solve named entities, irregulars, and fixed phrases
- rule modules solve productive behaviors
- keeping them separate makes profile inheritance and QA much clearer

### 4. Accented English should be modeled as profile overlays, not as a separate language pipeline

The architecture should treat non-native accented English as overlays on an English base profile where practical.

Reason:

- many accent-specific behaviors are modifications of an English base, not a new full language pipeline
- this supports future extensibility without duplicating the whole pronunciation system

### 5. Profile-aware planning remains engine-agnostic

The selected profile influences planner and realization behavior, but the planner must still emit app-owned artifacts rather than engine-native commands.

Reason:

- the pronunciation system must remain inspectable and portable across engines
- engine adapters are the final translation layer, not the ownership layer

## Architectural Rules

- English pronunciation behavior must be routed through an explicit profile model.
- A pronunciation profile must be selectable independently of any one engine implementation.
- Productive pronunciation behaviors must be modeled as rule modules, not only as lexicon entries.
- Resource layering must remain deterministic and inspectable.
- Document-time planning and voice/session realization must both be profile-aware.
- Accented-English support must be representable as profile overlays on an English base profile.
- Profile-aware planning must continue to emit engine-agnostic pronunciation and TTS artifacts.

## Current Implementation Gap

The current codebase now implements this architecture at an initial but real level.

At present:

- named English profiles, selection policy, resource layering, rule-module contracts, suffix allomorph handling, and profile-aware planning/realization are all explicit in code
- the implementation is still centered on an initial English profile set and a small number of productive modules
- future variant-specific stress/reduction overlays and accented-English coverage remain future work
- engine-specific phoneme inventories remain downstream adapter concerns rather than profile-owned data

## Governing Specifications

- [English Pronunciation Profile Model](../specifications/english-pronunciation-profile-model.md)
- [English Pronunciation Profile Selection Policy](../specifications/english-pronunciation-profile-selection-policy.md)
- [Pronunciation Resource Layering Policy](../specifications/pronunciation-resource-layering-policy.md)
- [Pronunciation Rule Module Contract](../specifications/pronunciation-rule-module-contract.md)
- [English Suffix Allomorph Module](../specifications/english-suffix-allomorph-module.md)
- [Document-Time Profile-Aware Pronunciation Planning](../specifications/document-time-profile-aware-pronunciation-planning.md)
- [Voice-Session Profile-Aware Pronunciation Realization](../specifications/voice-session-profile-aware-pronunciation-realization.md)

## Related Architecture

- [Pronunciation Planning and TTS Artifacts](pronunciation-planning-and-tts-artifacts.md)
- [Speech Enrichment and Narration](speech-enrichment-and-narration.md)
- [System Overview](system-overview.md)
