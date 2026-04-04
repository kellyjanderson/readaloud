# Dialogue Attribution, Character Casting, and Voice Library Metadata — 2026-04-03

## Topic

Research on how `Read Aloud` should grow from single-voice narration into:

- dialogue detection
- speaker attribution
- per-character voice assignment
- narrator-versus-character voice switching
- user-overridable cast management
- higher-fidelity voice-library metadata surfacing

## Findings

### 1. The current architecture is already close to the right boundary, but it stops before speaker identity

The current codebase already has:

- normalized sentence-first `SpeechDocument` segments
- document-time speech annotations
- discourse-role annotations such as `narration`, `quotation`, and `dialogue`
- a symbolic `NarrationState`
- a runtime that already carries `voiceId` per chunk and per progress event

What it does not yet have is a document-time model for:

- who is speaking
- which quoted spans belong to which speaker
- which stable character identity different mentions belong to
- which voice should be used for narrator versus each character

So this feature is not a greenfield speech subsystem. It is a missing layer between discourse-role inference and active voice/session realization.

### 2. Dialogue detection and speaker attribution should be a document-time sidecar, not a live playback guess

The system should not try to decide speaker identity in the hot playback path.

Reason:

- attribution is structural document analysis, not per-chunk acoustic work
- user override needs a stable document-scoped object model
- export, headless runs, and playback should all consume the same speaker truth

The right shape is a cached document-time sidecar containing:

- detected dialogue spans
- speaker attribution candidates
- stable character identities
- narrator identity
- confidence and provenance

### 3. A heuristic-first design is practical, but the provider boundary should remain open

There is strong prior art for quote attribution in long-form fiction. BookNLP is the clearest practical reference for the product domain because it explicitly supports:

- character name clustering
- coreference resolution
- quotation speaker identification
- book-length English documents

BookNLP also reports useful performance numbers for literary text in its public README, including speaker-attribution quality for both small and big models.

That said, BookNLP is a Python/NLP pipeline, not an embedded Flutter-native mobile subsystem. So it is better treated as:

- proof that the task is real and tractable
- a quality benchmark
- a future optional provider

The initial app architecture should therefore support:

- a local heuristic provider first
- a pluggable attribution-provider boundary later

### 4. The narrator must be modeled explicitly

Narration is not just the absence of detected dialogue.

The cast model should always include:

- one narrator entry
- zero or more detected character entries

Every spoken span should resolve to exactly one active speaker role:

- narrator
- detected character
- unattributed dialogue fallback

The fallback for unattributed dialogue should still be explicit, not an invisible failure mode.

### 5. Voice casting should be auto-generated but always user-overridable

Auto-casting is useful because most users will not want to assign a voice to every character by hand.

But it must remain advisory because:

- attribution can be wrong
- gender inference can be wrong or incomplete
- users may prefer a voice for aesthetic reasons that do not follow the system’s guess

So the right precedence is:

1. user override
2. stored document-specific cast decision
3. auto-cast policy
4. narrator/default fallback

### 6. Kokoro does publish usable quality metadata for voices

The current app does not surface voice quality beyond installed/bundled/download state.

Upstream Kokoro does publish more metadata. In the official `VOICES.md`, the voice catalog includes fields such as:

- `Traits`
- `Target Quality`
- `Training Duration`
- `Overall Grade`

That means “some voices are better than others” is not just anecdotal in current upstream materials.

For the voices currently bundled in `Read Aloud`, the upstream table currently lists:

- `af_heart` -> overall grade `A`
- `af_bella` -> overall grade `A-`
- `af_nicole` -> overall grade `B-`
- `am_michael` -> overall grade `C+`
- `bf_emma` -> overall grade `B-`
- `bm_fable` -> overall grade `C`

This is strong enough to justify surfacing quality information directly in the UI.

### 7. I did not find rich prose voice descriptions in the current official Kokoro metadata

The official Kokoro voice table includes compact trait markers and grading data, but not detailed prose descriptions for each voice.

So the app should model voice information as optional fields such as:

- quality grade
- target quality
- training duration
- short traits
- optional prose description

The UI should not assume every engine or every voice has a long description.

### 8. Voice metadata should be normalized at the app boundary, not scraped live by the UI

The current UI only receives:

- `VoiceProfile`
- `VoiceLibraryEntry`

Those models do not currently carry:

- quality grade
- traits
- description
- source metadata provenance

So this feature needs a stronger app-owned voice metadata model rather than letting the dialog infer meaning directly from raw engine ids.

## Decision

Adopt a new document-time subsystem for dialogue attribution and character casting, paired with an app-owned voice metadata model that can surface Kokoro quality data and future engine metadata without coupling UI behavior to one engine.

## Architectural Direction

The feature should be split into the following concerns:

1. Dialogue span detection
2. Speaker attribution and character clustering
3. Character cast registry with narrator identity
4. Auto-cast voice assignment policy
5. User override layer for narrator and characters
6. Multi-voice playback routing at segment/chunk boundaries
7. Voice-library metadata normalization and UI surfacing

## Implementation Notes

This research points toward:

- a document-time `DialogueAttributionSet` or equivalent sidecar rather than overloading the current minimal speech-annotation kinds
- a `CharacterCastRegistry` with stable document-scoped ids
- optional attribution providers, with heuristics first and richer NLP providers later
- an app-owned `VoiceMetadata` or `VoicePresentationMetadata` model layered onto `VoiceProfile`
- a narrator-plus-character override dialog, rather than forcing all casting through the current flat voice picker

## References

- Kokoro voice metadata  
  https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md

- BookNLP repository and usage documentation  
  https://github.com/booknlp/booknlp
