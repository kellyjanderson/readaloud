# Plain Text to Natural TTS Prior Art — 2026-03-29

Last updated: March 29, 2026
Status: Active research notes

## Topic

This document records prior art relevant to a core `Read Aloud` problem:

How do existing systems infer the structure needed for natural-sounding text-to-speech from plain or lightly structured text, and what does that imply for our internal document and chunking model?

## Findings

### 1. Existing TTS systems do not require rich source documents to produce usable speech

There is clear prior art across standards and platform APIs showing that useful TTS can be produced from plain text or lightly structured text.

- The Web Speech API accepts plain text via `SpeechSynthesisUtterance` and exposes boundary and `mark` events.
- Android `TextToSpeech.speak` accepts `CharSequence`, and Android `TtsSpan` exists specifically to attach additional speech metadata to text when the app knows more than the raw string.
- Apple speech APIs accept plain utterance strings and also support pronunciation hints through attributed speech content.

This supports the product assumption that most user documents will not arrive with rich TTS metadata already present, and that the app must infer or attach the missing speech structure itself.

### 2. The strongest formal prior art is structural, not algorithm-specific

The standards mostly define what information improves speech, not one mandatory algorithm for inferring it.

SSML 1.1 identifies the main categories of structure and control that matter for speech:

- paragraph structure via `p`
- sentence structure via `s`
- token and word structure via `token` and `w`
- pronunciation control via `phoneme`, `say-as`, and `sub`
- pause and cadence control via `break`
- timing hooks via `mark`
- prosody control via `prosody`

The important implication is that natural TTS is not just a property of the voice model. It also depends on a preprocessing stage that assigns structure and, when possible, speech-specific hints.

### 3. Sentence and word segmentation are established problems with standard prior art

There is strong prior art for default segmentation of plain text before speech generation.

- Unicode Text Segmentation (UAX #29) defines default word and sentence boundary rules.
- ICU Boundary Analysis implements word, sentence, line, and character boundary detection and explicitly notes abbreviation handling for false sentence boundaries.

This is important because it means we should not invent our own character-splitting heuristics as the primary model.

The ecosystem prior art says:

- detect sentence boundaries explicitly
- detect word boundaries explicitly
- treat abbreviations and punctuation as segmentation edge cases
- keep boundary detection as its own step before speech generation

### 4. The smallest practical speech unit is not a fixed character slice

The standards and platform prior art strongly argue against arbitrary character slicing as the primary speech unit.

Why:

- punctuation carries cadence information
- sentence boundaries carry prosodic information
- token boundaries matter for pronunciation
- abbreviations, decimals, initials, and clause punctuation all create ambiguity that plain character counts ignore

The most defensible base unit for natural speech is:

- sentence-sized speech segments

with these qualifiers:

- paragraph boundaries should still be preserved
- headings may form their own segments
- long sentences may need fallback splitting at clause boundaries
- token-level splitting is a last resort only

### 5. Plain text needs normalization before segmentation

Raw plain text often contains artifacts that will hurt speech quality unless normalized first.

Prior art and platform behavior together imply a normalization stage that handles:

- whitespace collapse
- blank-line to paragraph conversion
- smart treatment of line breaks that are visual wrapping rather than semantic breaks
- cleanup of extraction noise from PDF or DOCX import
- preservation of punctuation that affects pronunciation and cadence

This is especially important for imported PDFs, where line breaks and text runs often reflect layout extraction rather than author intent.

### 6. Platform APIs support attaching extra metadata after inference

Plain text does not need to stay plain once it enters the app.

Android `TtsSpan` is explicit evidence of this model: the app can keep the original displayed text while attaching speech-specific metadata for synthesis.

SSML provides the markup equivalent at the document level:

- keep the spoken structure and metadata separate from the original source text
- add extra pronunciation and timing hints where needed

This strongly supports our internal model direction:

- one representation for display
- one representation for speech
- explicit mapping between them

### 7. Prior art supports marks and boundaries for future synchronization

Both standards and browser APIs support synchronization hooks:

- SSML `mark`
- Web Speech API `mark` and boundary events

This does not mean every local engine will expose the same hooks, but it does show that progress mapping and future highlighting are not invented features. They follow an established speech-structure model.

## Implications

### Product Implications

- It is reasonable for `v1` to stay English-first.
- It is reasonable to expect natural enough speech from plain text and imported documents without requiring author-supplied TTS markup.
- The product should continue treating TTS preprocessing as part of the reading experience, not as an invisible implementation detail we can ignore.

### Architecture Implications

The current architecture direction is reinforced, not weakened.

We should keep:

- a normalized display model
- a normalized speech model
- explicit mapping between display position and speech position
- a preprocessing stage that can infer speech-specific structure from plain text

The research suggests that the speech-side model should be able to represent at least:

- paragraph boundaries
- sentence boundaries
- word spans
- speech normalization output
- optional speech hints such as pronunciation overrides, break strength, and future marks

### Specification Implications

The existing specifications should likely grow a more explicit speech-annotation layer later.

The likely direction is:

- `SpeechDocument` remains the canonical speech contract
- `SpeechSegment` remains sentence-first
- a future `SpeechAnnotation` concept may attach optional hints such as:
  - pronunciation override
  - explicit break
  - `say-as` style interpretation
  - synchronization mark

That does not need to be implemented immediately, but the specs should stay compatible with it.

### Chunking Implications

The smallest standard unit we should optimize around is:

- sentence-level segments

The smallest fallback unit we should tolerate is:

- clause-level split

The emergency-only fallback unit is:

- token-level split

The one unit we should not optimize around is:

- arbitrary character length

### PDF and Plain-Text Import Implications

For speech purposes, many imported documents will converge toward the same normalized speech representation even when their display representations remain very different.

That means:

- PDF, plain text, pasted text, DOCX, and RTF can all feed the same speech normalization pipeline
- the importer’s job is to preserve useful display structure while extracting speech structure cleanly
- the speech pipeline should not depend on source format once normalization is complete

## Working Conclusion

There is substantial prior art for inferring natural TTS structure from plain text.

The strongest common pattern is:

1. normalize text
2. infer paragraph, sentence, and word boundaries
3. attach optional speech metadata where needed
4. synthesize from those units

For `Read Aloud`, that means the right architectural unit is not a raw string and not a fixed-width chunk. It is a normalized speech document made of sentence-first segments with explicit mapping back to the displayed document.

## References

- SSML 1.1: https://www.w3.org/TR/speech-synthesis11/
- MDN `SpeechSynthesisUtterance`: https://developer.mozilla.org/en-US/docs/Web/API/SpeechSynthesisUtterance
- Android `TtsSpan`: https://developer.android.com/reference/android/text/style/TtsSpan
- Unicode Text Segmentation (UAX #29): https://www.unicode.org/reports/tr29/
- ICU Boundary Analysis: https://unicode-org.github.io/icu/userguide/boundaryanalysis/
- ICU Break Rules: https://unicode-org.github.io/icu/userguide/boundaryanalysis/break-rules.html
