# Cast-Aware Speech Range Routing

Status: final

## Overview

This specification defines how narrator and character cast assignments become explicit routed speech ranges with resolved voices.

## Backlink

Parent specification:

- [Multi-Voice Playback Routing](multi-voice-playback-routing.md)

## Scope

This specification covers:

- routed speech range derivation
- resolved voice assignment per range
- adjacent-range merge behavior
- parity across playback, export, and headless synthesis

## Behavior

The routing layer must resolve speech content into routed ranges that preserve:

- normalized segment and word boundaries
- resolved cast id
- resolved voice id

The default routing unit must be a structural speech boundary such as:

- dialogue span
- narration span
- segment boundary
- chunk subrange built from those boundaries

Adjacent routed ranges with the same effective voice should be merged when practical.

The same routing logic must be reused by:

- live playback
- export
- headless synthesis

## Constraints

- routing must not re-infer speaker identity live
- routing must preserve narrator fallback when attribution is absent or low-confidence
- routing must remain compatible with chunk planning and cache reuse

## Acceptance

- the app can derive explicit narrator/character voice ranges before generation
- adjacent identical-voice ranges can be merged without losing traceability
- playback, export, and headless flows can consume the same routed voice plan
