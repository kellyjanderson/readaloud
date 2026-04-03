# Kokoro Phoneme Inventory Adaptation

Last updated: April 3, 2026
Status: Final specification

## Overview

This specification defines how canonical internal IPA is adapted to Kokoro's accepted direct-phoneme inventory at the engine boundary.

## Backlink

Parent specification:

- [Engine Pronunciation Expression and Capability Adaptation](engine-pronunciation-expression-and-capability-adaptation.md)

## Scope

This specification covers:

- the ownership boundary between canonical internal IPA and Kokoro-facing phoneme payloads
- the required translation behavior for direct phoneme payloads sent to Kokoro
- traceability and cache requirements associated with that translation

This specification does not redefine document-time pronunciation planning, voice/session pronunciation realization, or plain-text G2P fallback behavior.

## Behavior

### Canonical Ownership Rule

App-owned pronunciation artifacts, lexical resources, and dictionary-backstop output may use standard IPA internally.

Kokoro/Misaki-specific phoneme symbols must not become the canonical internal pronunciation format.

### Adapter Translation Rule

When a realized pronunciation artifact is expressed through a direct phoneme payload to Kokoro, the engine adapter must translate canonical internal IPA to the Kokoro/Misaki inventory before tokenization.

This translation must happen at the engine boundary, not in document-time planning, voice/session realization, or stored artifact models.

### Initial Kokoro Mapping Rule

The first Kokoro adapter pass must at minimum support explicit translation for the phoneme classes that differ between canonical internal IPA and Kokoro's accepted inventory in current use.

That includes:

- stressed rhotic vowel adaptation such as `ɝ -> ɜɹ`
- affricate adaptation such as `dʒ -> ʤ`
- affricate adaptation such as `tʃ -> ʧ`

The mapping table may expand over time, but these current engine-facing differences must remain centralized in one adapter layer.

### Trace Rule

When the Kokoro-facing phoneme string differs from the canonical internal IPA string, diagnostics and debug trace output must preserve both:

- internal phoneme string
- engine phoneme string

This is required so pronunciation debugging can distinguish planner-owned intent from engine-facing adaptation.

### Cache Invalidation Rule

Generated-audio cache identity must change when the effective Kokoro-facing phoneme payload changes, even if the canonical internal artifact ids and text spans remain the same.

This prevents stale audio reuse from hiding a real engine-adapter phoneme change.

## Constraints

- The Kokoro phoneme inventory adapter must only apply to direct phoneme payloads.
- Plain-text fallback and normalized-spoken-text approximation remain separate translation paths.
- Canonical internal IPA must remain inspectable independently of Kokoro-specific symbol adaptation.

## Refinement Status

This is a final leaf specification.

## Child Specifications

No child specifications.

## Acceptance

- Canonical internal pronunciation data remains standard IPA rather than Kokoro-specific symbols.
- Direct phoneme payloads sent to Kokoro are adapted through one explicit boundary translation layer.
- Debug traces can show both internal and engine-facing phoneme strings when they differ.
- Cache invalidation reacts to Kokoro-facing phoneme payload changes.
