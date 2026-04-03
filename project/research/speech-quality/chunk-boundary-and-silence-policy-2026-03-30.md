# Chunk Boundary and Silence Policy — 2026-03-30

Last updated: March 30, 2026
Status: Active research notes

## Topic

This document answers the architecture question: what boundary policy should govern chunk joins so `Read Aloud` avoids exaggerated pauses without damaging natural phrasing?

## Findings

### 1. Boundary quality is a two-layer problem

The pause literature points to two different responsibilities:

- linguistic pause prediction before synthesis
- audio-boundary cleanup after synthesis

Pause placement and pause duration are part of phrasing. But once audio is chunked, the app also has to stop multiple silence sources from stacking.

Inference for `Read Aloud`:

- boundary policy should sit after synthesis but consume planner metadata about the intended break
- it should not invent phrasing from scratch

### 2. Sentence-first chunking is the default, clause fallback is the escape hatch

The research consistently argues against arbitrary character slicing.

The best priority order is:

1. keep whole paragraphs when feasible
2. otherwise keep whole sentences
3. otherwise split on clause-like boundaries
4. use token-level fallback only when required by hard engine limits

Inference for `Read Aloud`:

- chunk planning should carry an explicit boundary class on every join
- that class should survive into silence policy

### 3. Silence trimming should be asymmetric and capped, not blind

Blindly trimming all leading and trailing silence is too destructive.
Blindly preserving everything is what causes stacked pauses.

The safest policy is:

- aggressively trim pathological leading silence on noninitial chunks
- measure trailing and leading silence at joins
- cap the combined pause according to the intended boundary class
- preserve stronger joins for paragraph or heading transitions

Inference for `Read Aloud`:

- the app should reason about combined join silence, not each chunk in isolation

### 4. Overlap or crossfade should not be the default speech strategy

For speech, overlap and crossfade are risky because they can blur consonants, smear plosives, and hide join defects instead of fixing them.

Inference for `Read Aloud`:

- start with trim-and-cap, not overlap
- only consider overlap or crossfade as a special recovery tool if testing proves it helps a specific artifact class

### 5. The policy needs a notion of intended break strength

Standards prior art such as SSML already distinguishes break intent from raw silence.

Inference for `Read Aloud`:

- define a small boundary taxonomy such as:
  - none
  - weak
  - sentence
  - paragraph
  - section
- use that taxonomy to decide the maximum combined silence allowed at a join

### 6. The first chunk and resumed chunks are special cases

The first chunk of playback and the first chunk after a jump or replay should not inherit silence from the previous chunk, because there is no previous chunk in the current audible session.

Inference for `Read Aloud`:

- initial chunks should use only their own intentional opening behavior
- resumed chunks should be normalized as new audible starts

## Working Answer

The boundary policy for `Read Aloud` should be a hybrid:

### Before Synthesis

- plan chunks sentence-first
- carry boundary class metadata
- preserve paragraph and section transitions explicitly

### After Synthesis

- detect leading and trailing silence per chunk
- trim pathological leading silence on noninitial chunks
- cap total join silence by boundary class
- preserve stronger joins for paragraph and section breaks
- never add player-level gaps on top of already-finalized chunk audio

### Not Recommended as the Default

- overlap-add joins
- blanket crossfades
- fixed silence insertion independent of context
- trimming all silence to zero

## Implications

### Architecture Implications

- boundary policy deserves its own specification
- chunk metadata must include intended break class

### Specification Implications

Future specs should define:

- silence detection thresholds
- boundary taxonomy
- max combined silence per boundary class
- initial-chunk versus mid-session join rules
- cache format for corrected chunk audio

### Implementation Implications

- corrected audio should be cached after boundary policy runs
- join metrics should be recorded for debugging and evaluation
- replay should reuse corrected chunks, not redo boundary correction every time

## References

- SSML 1.1: https://www.w3.org/TR/speech-synthesis11/
- PauseSpeech: https://arxiv.org/abs/2306.07489
- Duration-Aware Pause Insertion for Text-to-Speech Systems: https://arxiv.org/abs/2302.13652
- A Study of Raters’ Sensitivity to Inter-sentence Pause Durations in American English Speech: https://research.google/pubs/a-study-of-raters-sensitivity-to-inter-sentence-pause-durations-in-american-english-speech/
- Evaluating Long-form Text-to-Speech: Comparing the Ratings of Sentences and Paragraphs: https://research.google/pubs/evaluating-long-form-text-to-speech-comparing-the-ratings-of-sentences-and-paragraphs/
