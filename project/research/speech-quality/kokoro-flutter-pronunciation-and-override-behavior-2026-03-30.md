# Kokoro Flutter Pronunciation and Override Behavior — 2026-03-30

Last updated: March 30, 2026
Status: Active research notes

## Topic

This document records research on the specific pronunciation problems observed in the current `Read Aloud` Kokoro Flutter path.

The immediate problems are:

- incorrect pronunciation of some `-ed` words such as `exclaimed`, `stomped`, and `retorted`
- unstable behavior when trying to inject explicit pronunciation overrides
- uncertainty about whether the Flutter tokenizer path preserves context well enough for natural pronunciation
- the need to understand which override mechanisms are safe for long-form reading without destabilizing playback

## Findings

### 1. The Flutter Kokoro package is built around `malsami`, but its main tokenizer path is not the same as running full-text G2P directly

The published `kokoro_tts_flutter` package describes itself as using ONNX Runtime plus advanced phonemization through `malsami`.

Its public usage example shows the normal path as:

- create `Tokenizer`
- call `tokenizer.phonemize(text, lang: 'en-us')`
- pass the resulting phoneme string into Kokoro

That is a valid supported path, but it is not equivalent to directly running the lower-level G2P over full text and preserving all higher-level input syntax.

From local source inspection of `kokoro_tts_flutter 0.2.0+1`, `Tokenizer.phonemize(...)` first splits text into words, punctuation, and whitespace, then phonemizes each word separately and preserves punctuation/whitespace literally.

Implication:

- this path is relatively simple and stable for playback
- but it is also more likely to lose full-text context and special pronunciation markup before the lower-level G2P can use it

### 2. `malsami` officially supports explicit pronunciation hints, but the documented format is markdown-style phoneme links

The `malsami` documentation explicitly says phonetic annotations are supported in markdown-link form:

- `[Word](/phonemes/)`

The docs show `EnglishG2P.convert('[Kokoro](/kˈOkəɹO/) models')`.

That means:

- explicit pronunciation hints are a supported upstream concept
- but the supported input form is a full-text annotation format, not a generic arbitrary token override API

### 3. The lower-level G2P engine used by Kokoro is designed for full-text processing, optional fallbacks, and contextual handling

The upstream `misaki` project shows the full English usage pattern as:

- instantiate English G2P
- pass full text into the G2P engine
- receive phonemes and tokens back

It also documents optional fallback to `espeak` for out-of-dictionary words.

This matters because the upstream conceptual model is:

- full text goes into G2P
- G2P is responsible for tokenization and contextual interpretation
- optional fallback is used when dictionaries do not cover a word well enough

That is structurally different from a wrapper that first splits text into independent word pieces and then phonemizes them one at a time.

### 4. `malsami` itself documents important limitations that map directly onto the failures we are seeing

The `malsami` docs explicitly list:

- English only
- dictionary assets are required
- no neural-network fallback for out-of-vocabulary words

Those limitations line up with the current symptoms:

- proper names can be stressed oddly
- some inflected forms are mishandled
- words not covered well by the dictionaries or heuristics can degrade sharply

The `-ed` pronunciation failures fit this pattern very well.

### 5. Upstream already has a documented issue where pronunciation-helper markup can break on long text

The upstream Kokoro issue tracker has a report that pronunciation helpers in the form:

- `[Kokoro](/kˈOkəɹO/)`

work for short text but can fail on very long text, producing both the original and helper pronunciation. The reported workaround is to split long text and process pieces separately.

This is strong evidence that pronunciation-helper markup is not robust enough to be our primary production override mechanism for long-form book-style reading, even before any Flutter wrapper behavior is added on top.

### 6. Local inspection suggests the `phonemize(...)` and `phonemizeWithTokens(...)` paths are not equivalent, and that difference is operationally important

From local dependency inspection of `kokoro_tts_flutter 0.2.0+1`:

- `Tokenizer.phonemize(...)` uses an internal `_advancedSplit(...)` pass and processes words separately
- `Tokenizer.phonemizeWithTokens(...)` routes through the lower-level G2P conversion path more directly
- comments in the package source indicate the relationship between the two paths is not fully aligned yet, and the `phonemizeWithTokens(...)` method may need to align with `phonemize(...)` or be deprecated later

This is an important project-local finding.

Implication:

- `phonemizeWithTokens(...)` may be more semantically correct for custom annotations and context
- but it is a higher-risk drop-in replacement for a live playback engine if the rest of the system has already been built and stabilized around `phonemize(...)`

### 7. The safest current override mechanism for the live app is lexicon augmentation, not inline annotation injection

Given the upstream and local findings together:

- inline annotation markup is supported in principle
- but it is brittle on long-form inputs
- and the current Flutter wrapper path can interfere with it

Lexicon augmentation is therefore the safest near-term strategy for isolated words and names:

- it fits the token-by-token `phonemize(...)` path
- it avoids markup entering the playback text stream
- it does not rely on special inline syntax surviving tokenization

This makes lexicon entries the best current fit for:

- `Elliot`
- `exclaimed`
- `stomped`
- `retorted`

### 8. Function words such as `for` should not be globally overridden in the current architecture

`for` is not like a proper name or a stubborn inflected content word.

It is a function word whose pronunciation can vary with context, reduction, and surrounding phrasing. A global word-level override risks making many normal cases worse.

No upstream source found in this pass suggests that a blanket lexical replacement for `for` is the right solution.

My inference is:

- `for` should be treated as a context-sensitive pronunciation/prosody problem
- not as a stable global lexicon-entry problem unless repeated evidence shows the same fixed pronunciation is always preferred

### 9. The long-term solution is likely a dedicated full-text G2P / pronunciation stage, separate from the live playback queue

The evidence now points to a structural split:

- stable playback wants a simple, predictable, queue-safe path
- strong pronunciation control wants full-text contextual G2P, override handling, and richer token metadata

Trying to force all of that into the playback queue’s live tokenization step is high risk.

The cleaner long-term direction is:

- perform pronunciation planning earlier
- on bounded sentence/segment windows or other explicit units
- then hand stable phoneme/token outputs into playback generation

That would make pronunciation work more controllable without destabilizing queue order and chunk lifecycle.

## Implications

### Immediate Implications

- Keep the live playback path on the stable `Tokenizer.phonemize(...)` flow for now.
- Use lexicon entries for isolated problem words and names.
- Do not inject markdown pronunciation helpers directly into the live playback text path right now.
- Treat `for` and similar function words as context-sensitive cases that need a different strategy than simple word replacement.

### Architecture Implications

This issue is not only a pronunciation problem. It exposes a boundary problem between:

- text normalization
- pronunciation planning
- tokenization
- chunk generation
- playback safety

If we want stronger pronunciation control without regressions, the architecture likely needs a separate pronunciation-planning stage rather than ad hoc inline override logic inside the runtime path.

### Implementation Implications

The safest implementation order from this research is:

1. preserve the stable playback tokenizer path
2. use lexicon-based fixes for high-confidence isolated words
3. collect more exact sentence-level failures
4. if context-sensitive pronunciation remains a major problem, design a dedicated full-text G2P layer before changing the runtime path again

## References

### External Sources

- `kokoro_tts_flutter` package page: https://pub.dev/packages/kokoro_tts_flutter/versions/0.2.0%2B1
- `malsami` API docs: https://pub.dev/documentation/malsami/latest/
- `misaki` repository: https://github.com/hexgrad/misaki
- Upstream long-text pronunciation-helper issue: https://github.com/hexgrad/kokoro/issues/42

### Local Source Inspection

These findings were also informed by inspection of the currently installed dependency versions in the local project environment:

- `kokoro_tts_flutter 0.2.0+1`
- `malsami 0.0.3`

The relevant local observations were:

- `Tokenizer.phonemize(...)` splits text into word/punctuation/whitespace parts before phonemizing words
- `Tokenizer.phonemizeWithTokens(...)` follows a different route through the lower-level G2P conversion path
- the current package comments suggest those two paths are not fully aligned yet
