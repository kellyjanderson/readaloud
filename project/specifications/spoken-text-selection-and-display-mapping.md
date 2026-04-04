# Spoken Text Selection and Display Mapping

Status: final

## Overview

This specification defines how playback progress becomes a visible spoken selection mapped back into display content.

## Backlink

Parent specification:

- [Spoken Text Highlighting and Reading Focus](spoken-text-highlighting-and-reading-focus.md)

## Scope

This specification covers:

- spoken selection derivation from progress events
- mapping from spoken ranges to display ranges
- fallback precision from word to segment to block

## Behavior

The controller must derive spoken selection state from progress events using:

- normalized speech ids and word ranges
- normalized display/speech mapping data

The resulting selection model must support a fallback ladder:

1. current spoken word
2. current spoken phrase or segment
3. current visible block

The mapping layer must not depend on:

- reparsing rendered HTML
- reparsing flattened reader text

## Constraints

- spoken selection must remain traceable to normalized ids
- degraded mapping must still result in useful visible state
- selection mapping must remain engine-agnostic above the progress-event contract

## Acceptance

- the app can derive a visible spoken selection from progress events
- the selection can be mapped back into normalized display content
- lower-confidence mappings still produce segment- or block-level selection
