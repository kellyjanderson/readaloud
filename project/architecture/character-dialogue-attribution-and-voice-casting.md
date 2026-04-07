# Character Dialogue Attribution and Voice Casting

Last updated: April 3, 2026
Status: Active architecture

## Purpose

This document defines how `Read Aloud` should detect dialogue, infer speakers, maintain a document cast, and route narrator and character speech to different voices.

## Overview

Single-voice narration is no longer sufficient for the product direction.

The app needs an internal casting layer that can:

- detect direct-speech spans
- infer likely speakers
- cluster references into stable character identities
- maintain an explicit narrator identity
- assign voices to narrator and characters
- allow the user to override those assignments
- route playback and export through those resolved voices without re-inferring cast decisions live

This layer belongs between speech enrichment and active playback routing.

The document itself must own speaker and cast attribution results once import finishes.

That means the imported document should carry first-class attribution structures that say which spoken ranges belong to narration, which belong to attributed characters, and which remain unattributed dialogue fallback. Playback may still resolve current effective voice ids from narrator choice and user overrides, but it must not decide who is speaking a range during live reading.

## Components

### Dialogue Span Detection

Responsibilities:

- detect quoted or dialogue-like spans in normalized speech content
- preserve span-to-segment and span-to-word mapping
- distinguish narration from direct speech, unattributed dialogue, and quoted text where possible

### Speaker Attribution

Responsibilities:

- infer which nearby mention or entity is the most likely speaker for a dialogue span
- preserve attribution confidence, rule trace, and evidence spans
- apply an ordered rule ladder rather than one opaque score
- allow explicit same-sentence tags to outrank weaker heuristics
- support lower-priority paragraph ownership, alternation, pronoun resolution, and speaker persistence fallback
- allow unattributed dialogue to remain explicit rather than silently collapsing into narrator

### Character Registry

Responsibilities:

- cluster references that belong to the same story character
- keep one stable document-scoped id per detected character
- preserve visible display label, observed aliases, and supporting evidence
- preserve one explicit narrator entry even when no dialogue is found
- consolidate obvious near-duplicate longer-name variants conservatively when document evidence supports that merge
- preserve optional document-owned identity metadata extracted in a later pass after alias consolidation
- keep gender identity, pronoun profile, and descriptor evidence as separate data rather than one collapsed inferred-gender field

### Voice Casting Policy

Responsibilities:

- assign a narrator voice
- assign default voices to detected characters
- use locale and available voice metadata as inputs
- use document-owned character identity metadata only when it has been explicitly and conservatively extracted
- keep auto-casting deterministic within one document version
- support a user-visible processing phase while document-load cast analysis is still underway

### User Override Layer

Responsibilities:

- allow narrator and character voice assignments to be changed by the user
- keep user overrides separate from automatic attribution confidence
- apply user choice as the highest-precedence cast decision

### Multi-Voice Playback Routing

Responsibilities:

- consume document-owned cast-attributed speech ranges rather than rescanning dialogue context live
- resolve each spoken segment window to the correct active voice
- switch voices at dialogue and narration boundaries
- merge adjacent ranges when the resolved voice is identical
- reuse the same routing behavior for playback, export, and headless synthesis

### Voice Metadata Catalog

Responsibilities:

- preserve app-owned presentation metadata about voices
- preserve explicit voice gender metadata when it can be derived responsibly
- surface optional quality, traits, and description data without coupling UI behavior to one engine
- make the cast-management UI and voice library dialog data-driven

## Relationships

- dialogue detection depends on normalized speech segments and existing discourse-role inference
- speaker attribution depends on dialogue spans plus nearby lexical and structural context
- character registry depends on attribution results and mention clustering
- document-owned voice attribution depends on dialogue spans, speaker attribution, and the character registry
- voice casting depends on the character registry, narrator identity, and installed/available voice metadata
- voice casting may use explicit app-owned voice gender metadata plus document-owned character identity extraction when that extraction is explicit, conservative, and separately traceable from pronoun evidence
- user overrides apply after auto-casting and before runtime chunk routing
- playback/export/headless generation consume document-owned attribution plus resolved voice assignments; they do not infer speakers themselves

The intended sequencing is:

- document load builds dialogue and cast truth first
- a later pass extracts character identity metadata from canonicalized character entities
- the app may surface progress while that work is still running
- live playback starts from the resulting document-owned attribution rather than improvising cast truth mid-read

## Data Flow

```text
SpeechDocument
  -> dialogue span detection
  -> speaker attribution
  -> character registry
  -> document-owned cast attribution
  -> narrator + character cast registry
  -> auto-cast voice assignment
  -> user override layer
  -> multi-voice chunk routing
  -> runtime generation and playback
```

## Cross-Domain Solutions

### 1. Speaker identity is not a UI-only concern

The app must not keep speaker attribution only as dialog-local UI state.

Reason:

- playback, export, and headless runs need the same speaker truth
- user overrides must persist against stable character identity, not ephemeral widgets

### 1a. Voice attribution is document-owned state, not controller-local reconstruction

The app must not reconstruct speaker ownership of spoken ranges inside the reader controller each time playback is prepared.

Reason:

- speaker ownership is part of the imported document meaning, not a transient playback convenience
- export and headless generation need the same narrator-versus-character boundaries as live playback
- document-owned attribution is the only clean place to guarantee that quoted text and surrounding narration stay distinct

### 2. Narrator is a first-class cast member

The system must not treat narration as a null speaker.

Reason:

- narrator voice choice is part of the user-facing cast model
- unattributed dialogue fallback needs a stable contrast with narrator speech

### 3. Auto-casting is advisory, not authoritative

The system must provide useful automatic assignments without making them impossible to correct.

Reason:

- speaker attribution will sometimes be wrong
- users may prefer a different voice for style reasons even when attribution is correct

### 4. Attribution providers should be replaceable

The app must not hard-wire the entire architecture to one heuristic pass or one external NLP model.

Reason:

- lightweight local heuristics are the practical first implementation
- richer NLP pipelines may become desirable later

### 5. Voice switching should happen at structural speech boundaries

The system must not treat per-character casting as arbitrary mid-word or mid-phrase voice swapping.

Reason:

- the natural switching unit is narration/dialogue span or segment boundary
- chunk planning and caching remain more stable when voice routing is boundary-aware

## Architectural Rules

- Dialogue attribution is document-time work and should be cached with the normalized document version when practical.
- Document-owned cast attribution must be materialized at document load and carried by the internal document structure.
- Character ids must remain stable within one normalized document version.
- Every spoken span must resolve to narrator, a detected character, or explicit unattributed-dialogue fallback.
- User overrides must win over auto-cast policy.
- Voice routing must be explicit and inspectable in playback/export diagnostics.
- Voice metadata must be modeled as optional app-owned fields rather than UI-private ad hoc parsing.

## Current Implementation Gap

The current implementation now includes:

- dialogue span detection
- heuristic speaker attribution with local before/after quoted-dialogue context scanning
- a narrator-plus-character cast registry
- conservative consolidation of obvious longer-name variants into one character entry
- optional narrow referential-gender inference from alias-linked local text evidence
- the richer character identity extraction model is not yet implemented; the current code still uses a much narrower referential-gender shortcut and must be upgraded
- context-aware automatic casting that consumes app-owned voice metadata and cast metadata
- document-owned cast attribution materialized on the imported document structure
- routed multi-voice playback planning and live routed synthesis
- surfaced voice metadata and override UI

The main remaining gaps are:

- broader quality and sophistication gaps beyond the current release leaves, including:
- richer cross-paragraph character clustering beyond conservative typo and alias handling
- stronger speaker attribution and referential inference than the current lightweight local heuristics
- the new ordered speaker-attribution rule system and richer character-identity extraction model are still not implemented end-to-end
- any future culturally sensitive voice metadata remains intentionally out of scope until explicitly designed

## Governing Specifications

- [Dialogue Span and Speaker Attribution](../specifications/dialogue-span-and-speaker-attribution.md)
- [Character Cast Registry and Voice Assignment](../specifications/character-cast-registry-and-voice-assignment.md)
- [Multi-Voice Playback Routing](../specifications/multi-voice-playback-routing.md)
- [Voice Library Metadata and Information Surfacing](../specifications/voice-library-metadata-and-information-surfacing.md)
