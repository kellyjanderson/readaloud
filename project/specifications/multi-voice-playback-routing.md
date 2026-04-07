# Multi-Voice Playback Routing

Status: draft

## Overview

This specification refines cast-aware voice routing into implementable units.

## Backlink

Parent architecture:

- [Character Dialogue Attribution and Voice Casting](../architecture/character-dialogue-attribution-and-voice-casting.md)

## Scope

This specification covers:

- document-owned voice attribution materialization
- cast-aware speech-range routing
- merge behavior for adjacent identical voice ranges
- routed progress and diagnostics
- observable running-app voice switching

## Behavior

The parent branch now delegates detailed implementation to child specifications.

In particular:

- document-load voice attribution materialization belongs to its own leaf
- cast-aware speech range routing belongs to its own leaf
- quoted dialogue voice segmentation belongs to its own leaf
- voice-routed progress and diagnostics belong to its own leaf
- observable running-app multi-voice playback switching belongs to its own leaf

This parent specification keeps only the branch-level contract that narrator and character assignments become document-owned attribution data first, then explicit voice-routing decisions shared by playback, export, and headless flows.

## Constraints

- playback routing must not re-infer speaker identity live
- routing must remain compatible with chunk caching and progress reporting
- routing must preserve narrator fallback when attribution is absent or low-confidence

## Refinement Status

Refinement complete for the current planned branch.

## Child Specifications

- [Document-Load Voice Attribution Materialization](document-load-voice-attribution-materialization.md)
- [Cast-Aware Speech Range Routing](cast-aware-speech-range-routing.md)
- [Quoted Dialogue Voice Segmentation](quoted-dialogue-voice-segmentation.md)
- [Voice-Routed Progress and Diagnostics](voice-routed-progress-and-diagnostics.md)
- [Running-App Multi-Voice Playback Switching](running-app-multi-voice-playback-switching.md)

## Acceptance

- the app can generate and play narrator and character speech with different voices in one reading session
- the imported document owns narrator-versus-character attribution before live playback begins
- export and headless synthesis follow the same cast-aware routing decisions as live playback
- the running app has an explicit final leaf for observable narrator-versus-character voice switching
- the remaining work in this branch is represented by final leaf specifications
