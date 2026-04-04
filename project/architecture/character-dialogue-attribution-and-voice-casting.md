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

## Components

### Dialogue Span Detection

Responsibilities:

- detect quoted or dialogue-like spans in normalized speech content
- preserve span-to-segment and span-to-word mapping
- distinguish narration from direct speech, unattributed dialogue, and quoted text where possible

### Speaker Attribution

Responsibilities:

- infer which nearby mention or entity is the most likely speaker for a dialogue span
- preserve attribution confidence and provenance
- allow unattributed dialogue to remain explicit rather than silently collapsing into narrator

### Character Registry

Responsibilities:

- cluster references that belong to the same story character
- keep one stable document-scoped id per detected character
- preserve visible display label, observed aliases, and supporting evidence
- preserve one explicit narrator entry even when no dialogue is found

### Voice Casting Policy

Responsibilities:

- assign a narrator voice
- assign default voices to detected characters
- use locale and future voice metadata as inputs
- keep auto-casting deterministic within one document version

### User Override Layer

Responsibilities:

- allow narrator and character voice assignments to be changed by the user
- keep user overrides separate from automatic attribution confidence
- apply user choice as the highest-precedence cast decision

### Multi-Voice Playback Routing

Responsibilities:

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
- voice casting depends on the character registry, narrator identity, and installed/available voice metadata
- voice casting may use explicit app-owned voice gender metadata, but more socially sensitive cultural or identity metadata must remain out of scope until explicitly designed
- user overrides apply after auto-casting and before runtime chunk routing
- playback/export/headless generation consume routed voices; they do not infer speakers themselves

## Data Flow

```text
SpeechDocument
  -> dialogue span detection
  -> speaker attribution
  -> character registry
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
- Character ids must remain stable within one normalized document version.
- Every spoken span must resolve to narrator, a detected character, or explicit unattributed-dialogue fallback.
- User overrides must win over auto-cast policy.
- Voice routing must be explicit and inspectable in playback/export diagnostics.
- Voice metadata must be modeled as optional app-owned fields rather than UI-private ad hoc parsing.

## Current Implementation Gap

The current implementation is still single-voice at the session level:

- discourse-role inference exists, but no speaker-attribution or character-registry sidecar exists
- `NarrationState` tracks delivery continuity, not cast identity
- the reader controller owns one selected voice, not narrator-plus-character assignments
- the voice library dialog shows installation state, but not quality/traits/description metadata

## Governing Specifications

- [Dialogue Span and Speaker Attribution](../specifications/dialogue-span-and-speaker-attribution.md)
- [Character Cast Registry and Voice Assignment](../specifications/character-cast-registry-and-voice-assignment.md)
- [Multi-Voice Playback Routing](../specifications/multi-voice-playback-routing.md)
- [Voice Library Metadata and Information Surfacing](../specifications/voice-library-metadata-and-information-surfacing.md)
