# Multi-Voice Playback Routing

Status: draft

## Overview

This specification refines cast-aware voice routing into implementable units.

## Backlink

Parent architecture:

- [Character Dialogue Attribution and Voice Casting](../architecture/character-dialogue-attribution-and-voice-casting.md)

## Scope

This specification covers:

- cast-aware speech-range routing
- merge behavior for adjacent identical voice ranges
- routed progress and diagnostics

## Behavior

The parent branch now delegates detailed implementation to child specifications.

In particular:

- cast-aware speech range routing belongs to its own leaf
- voice-routed progress and diagnostics belong to its own leaf

This parent specification keeps only the branch-level contract that narrator and character assignments become explicit voice-routing decisions shared by playback, export, and headless flows.

## Constraints

- playback routing must not re-infer speaker identity live
- routing must remain compatible with chunk caching and progress reporting
- routing must preserve narrator fallback when attribution is absent or low-confidence

## Refinement Status

Requires refinement.

## Child Specifications

- [Cast-Aware Speech Range Routing](cast-aware-speech-range-routing.md)
- [Voice-Routed Progress and Diagnostics](voice-routed-progress-and-diagnostics.md)

## Acceptance

- the app can generate and play narrator and character speech with different voices in one reading session
- export and headless synthesis follow the same cast-aware routing decisions as live playback
- the remaining work in this branch is represented by final leaf specifications
