# Narration State and Voice-Specific Realization — 2026-03-30

Last updated: March 30, 2026
Status: Active research notes

## Topic

This document answers two related architecture questions:

- what `NarrationState` should remember between chunks
- whether `Read Aloud` should maintain voice-specific rule sets of its own

## Findings

### 1. Long-form coherence needs memory, but not unlimited memory

The long-form TTS literature is very consistent on one point: sentence-by-sentence synthesis without context tends to sound locally fine and globally inconsistent.

The recurring needs are:

- continuity of speaking style across adjacent sentences
- stable handling of paragraph transitions
- context-sensitive pauses
- reduced sentence-reset feel

But the research does not imply that the application should try to reproduce the model’s internal acoustic state.

Inference for `Read Aloud`:

- `NarrationState` should be a lightweight application-level state
- it should model discourse continuity and recent realization choices
- it should not try to become a fragile pseudo-acoustic embedding store

### 2. The most valuable narration state is symbolic and local

For the app layer, the most useful remembered state is likely:

- current section mode
  - heading transition
  - body prose
  - list reading
  - caption or aside
- dialogue or quotation mode
- recent boundary class
  - clause break
  - sentence break
  - paragraph break
- recent emphasis density
- recent speaking-rate context
- whether the last chunk ended in unresolved continuation
  - comma
  - colon
  - em-dash-like interruption
  - open quote or parenthetical

This is enough to improve continuity decisions without pretending the app owns the model’s internals.

### 3. Voice-specific rule sets are useful for pronunciation, weak for style

There is strong prior art for application-owned pronunciation help:

- SSML `phoneme`
- SSML `say-as`
- Android `TtsSpan`
- Misaki inline phoneme markup

There is much weaker evidence that an app like `Read Aloud` should maintain deep per-voice prosody tables.

Inference for `Read Aloud`:

- maintain small, explicit voice-family or accent-specific pronunciation overrides
- maintain text-normalization exceptions for recurring problem tokens
- do not start with per-voice pause-style or emphasis-style rule tables unless testing proves a real need

### 4. The most practical split is generic intent first, voice-specific realization second

The app should infer generic speech intent once:

- this span is probably emphatic
- this boundary is probably a paragraph break
- this token is a date
- this token may be ambiguous or needs pronunciation help

Then the selected voice and rate decide how to realize that intent.

Inference for `Read Aloud`:

- `NarrationState` should carry realized outcomes from recent chunks
- the voice-specific layer should interpret generic intent rather than re-infer document meaning from scratch

### 5. Kokoro specifically pushes more responsibility up into the app

Kokoro gives us:

- voice selection
- speed control
- language/accent selection
- phoneme injection or override paths via Misaki
- chunk segmentation control

It does not expose a public, rich narration-state API for:

- persistent style embeddings
- explicit pause-strength control
- mark callbacks
- direct prosody contour control

Inference for `Read Aloud`:

- the app’s narration state should focus on chunk planning, join policy, and pronunciation/emphasis decisions
- we should not design around hidden or speculative Kokoro state

## Working Answer

### `NarrationState` Should Remember

- current discourse mode
- recent boundary class
- continuation-versus-closure status
- recent emphasis intensity
- recent realized rate
- nearby quote/dialogue state
- recently selected pronunciation or ambiguity resolutions where continuity matters

### `NarrationState` Should Not Remember

- raw audio history as a long rolling window
- speculative acoustic embeddings owned only by the current engine
- per-sentence state that cannot survive voice changes or replay

### Voice-Specific Rules We Should Own

- accent-specific pronunciation overrides
- recurring term dictionaries
- optional per-voice exclusion or warning metadata if a voice performs poorly on specific classes

### Voice-Specific Rules We Should Not Own Yet

- large hand-authored prosody tables
- per-voice pause personalities
- model-internal style approximations

## Implications

### Architecture Implications

- `NarrationState` should be specified as a small symbolic state object
- base annotations and voice realization remain separate layers

### Specification Implications

Future specs should define:

- `NarrationState` fields and reset rules
- pronunciation override precedence
- which voice/session changes invalidate realization state

### Implementation Implications

- replay from the start should reset `NarrationState`
- 30-second jumps should preserve only the state derivable from the new entry point, not stale trailing context
- voice changes should keep generic document annotations but rebuild realization state

## References

- SSML 1.1: https://www.w3.org/TR/speech-synthesis11/
- Android `TtsSpan`: https://developer.android.com/reference/android/text/style/TtsSpan
- kokoro README: https://github.com/hexgrad/kokoro
- misaki README: https://github.com/hexgrad/misaki
- Global Style Tokens: https://research.google/pubs/style-tokens-unsupervised-style-modeling-control-and-transfer-in-end-to-end-speech-synthesis/
- Context-Aware Coherent Speaking Style Prediction for Audiobook Speech Synthesis: https://arxiv.org/abs/2304.06359
- Improving Speech Prosody of Audiobook TTS with Acoustic and Textual Contexts: https://arxiv.org/abs/2211.02336
- Text-aware and Context-aware Expressive Audiobook Speech Synthesis: https://arxiv.org/abs/2406.05672
- Long-Context Speech Synthesis with Context-Aware Memory: https://arxiv.org/abs/2508.14713
