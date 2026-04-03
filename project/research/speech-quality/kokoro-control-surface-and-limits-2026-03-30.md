# Kokoro Control Surface and Limits — 2026-03-30

Last updated: March 30, 2026
Status: Active research notes

## Topic

This document answers the architecture question: how much control does Kokoro actually give `Read Aloud`, and where does the app need to own behavior above the engine?

## Findings

### 1. Kokoro’s public control surface is real, but fairly narrow

The published Kokoro examples expose a usable but modest set of controls:

- voice selection
- language/accent selection
- speed
- input text
- chunk splitting strategy
- direct voice tensors in the Python implementation

The ONNX implementation exposes a similar shape:

- text
- voice
- speed
- language

That is enough for a local, multi-voice reader, but it is not a full narration-control API.

### 2. Kokoro meaningfully supports pronunciation overrides

This is the most important positive finding.

Kokoro uses Misaki for G2P, and Misaki documents:

- inline pronunciation markup
- explicit English phoneme inventory
- accent-specific English behavior
- fallback handling for out-of-dictionary words

Inference for `Read Aloud`:

- we can build real pronunciation correction and term-specific overrides on top of Kokoro
- the internal speech model should preserve pronunciation-override hooks as a first-class concept

### 3. Kokoro does not expose SSML-like prosody control directly

The official docs and public examples do not advertise first-class support for:

- SSML `break`
- SSML `prosody`
- SSML `emphasis`
- SSML `mark`
- long-lived narrator-style state injection

Inference for `Read Aloud`:

- the app cannot assume that internal pause, emphasis, or narration annotations map directly to engine-level controls
- much of the quality work needs to happen through:
  - preprocessing
  - chunk planning
  - pronunciation overrides
  - boundary policy
  - caching and reuse

### 4. For Kokoro, chunk boundaries are part of the control surface

Because direct prosody controls are limited, chunk design becomes more important.

The app can still affect perceived quality through:

- what text is grouped together
- where sentence and paragraph boundaries land
- whether a boundary is preserved inside one synthesis request or forced into a join
- whether the next chunk is prepared with enough look-ahead

Inference for `Read Aloud`:

- chunk planning is not a transport detail
- it is one of the main ways the app steers Kokoro quality

### 5. Voice-specific behavior should stay narrow and explicit

There is strong evidence for owning:

- accent-specific pronunciation overrides
- recurring proper-name and domain-term dictionaries
- fallback rules for out-of-dictionary terms

There is weak evidence for owning:

- hand-authored voice personalities
- deep per-voice pause tuning
- complex prosody rules per voice

Inference for `Read Aloud`:

- start with accent-family overrides and known-problem dictionaries
- treat broader voice-specific styling as future work driven by testing

## Working Answer

Kokoro can reliably honor:

- selected voice
- selected rate
- chosen accent/language variant
- direct pronunciation help through phoneme-aware input
- chunk grouping decisions

Kokoro does not currently appear to give the app direct control over:

- pause-strength primitives
- emphasis primitives
- paragraph-level narrator style state
- highlight or mark callbacks
- explicit prosody contours

For `Read Aloud`, that means:

- pronunciation handling is worth building
- rich speech intent should still exist in our architecture
- translation from internal speech intent to Kokoro output will often be indirect rather than one-to-one

## Implications

### Architecture Implications

- keep `SpeechAnnotationSet` engine-agnostic
- give the Kokoro realization layer explicit responsibility for “best effort translation” of internal speech intent

### Specification Implications

Future Kokoro-facing specs should define:

- pronunciation override precedence
- how chunk plans are shaped for Kokoro
- what realization data is ignored versus approximated by the Kokoro adapter

### Implementation Implications

- prioritize pronunciation correction tooling before more speculative prosody tooling
- do not block architecture on unavailable engine controls
- keep room for a future engine that supports richer SSML-like controls

## References

- kokoro README: https://github.com/hexgrad/kokoro
- kokoro-onnx README: https://github.com/thewh1teagle/kokoro-onnx
- kokoro-onnx example: https://github.com/thewh1teagle/kokoro-onnx/blob/main/examples/save.py
- misaki README: https://github.com/hexgrad/misaki
- Misaki English phoneme inventory: https://github.com/hexgrad/misaki/blob/main/EN_PHONES.md
- SSML 1.1: https://www.w3.org/TR/speech-synthesis11/
