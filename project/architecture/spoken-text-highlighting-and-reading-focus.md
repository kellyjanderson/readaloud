# Spoken Text Highlighting and Reading Focus

Last updated: April 3, 2026
Status: Active architecture

## Purpose

This document defines how `Read Aloud` should highlight the text currently being spoken and keep the visible reading surface aligned with playback.

## Overview

The app already knows:

- what speech segment and word range is active
- how normalized speech maps back to visible display content

What it does not yet do is turn that knowledge into stable UI behavior.

This architecture defines the missing layer between playback progress and reader-surface presentation.

## Components

### Spoken Progress State

Responsibilities:

- consume runtime progress events
- preserve the current spoken segment id and word range
- preserve current voice and rate context for follow-along decisions

### Progress-to-Display Mapper

Responsibilities:

- resolve spoken segment and word ranges to visible display ranges
- use normalized display/speech mappings rather than renderer-private string search
- preserve confidence and fallback level for the resolved visible range

### Highlight Model

Responsibilities:

- represent the active spoken selection in UI-friendly form
- support word-, segment-, and block-level highlight precision
- preserve enough information for debugging and later accessibility behavior

### Reading Focus Controller

Responsibilities:

- decide when the viewport should follow playback
- avoid jitter from per-word scrolling
- pause or relax follow behavior when the user manually scrolls
- resume follow mode based on explicit policy rather than accidental motion

### Reader Surface Rendering

Responsibilities:

- paint the active spoken range
- degrade gracefully when only lower-confidence mapping is available
- keep highlight presentation separate from playback timing logic

## Relationships

- spoken progress state depends on playback/runtime events
- progress-to-display mapping depends on `SpeechDocument`, `DisplayDocument`, and `PositionMap`
- the highlight model depends on mapping output, not on raw HTML
- the reading focus controller consumes the same highlight state but applies separate viewport policy

## Data Flow

```text
playback progress event
  -> spoken progress state
  -> progress-to-display mapper
  -> highlight model
  -> reader surface painting
  -> reading focus controller
  -> viewport updates
```

## Cross-Domain Solutions

### 1. Highlighting is a normalized-content feature, not an HTML trick

The system must not anchor follow-along behavior to renderer-private HTML substring search.

Reason:

- HTML conversion is a presentation detail
- normalized mapping is the durable cross-format contract

### 2. Precision and user comfort are different concerns

The system must separate:

- precise spoken-range updates
- comfortable viewport movement

Reason:

- per-word progress can be frequent
- per-word scrolling is visually noisy

### 3. Degraded mapping still needs useful feedback

The app must not fail silently when exact word-level mapping is unavailable.

Reason:

- some imported formats or future engine paths may have weaker mapping confidence
- segment or block highlighting is still better than no follow-along state

## Architectural Rules

- Highlight state must derive from normalized ids and ranges.
- The UI must not re-derive spoken ranges from flattened `displayHtml` or `speakableText`.
- The mapping layer must support a fallback ladder from word to segment to block.
- Viewport follow policy must be explicit and suspendable.
- Pause must freeze the visible highlight at the last known spoken range until playback resumes or resets.

## Current Implementation Gap

The core branch is now implemented:

- follow-along rendering is active
- reading focus and recenter behavior are active
- the reading surface now preserves readable contrast across appearance modes

Future work in this area should focus on additional polish or accessibility improvements rather than missing core branch behavior.

## Governing Specifications

- [Playback Progress and Jump Mapping](../specifications/playback-progress-and-jump-mapping.md)
- [Spoken Text Highlighting and Reading Focus](../specifications/spoken-text-highlighting-and-reading-focus.md)
