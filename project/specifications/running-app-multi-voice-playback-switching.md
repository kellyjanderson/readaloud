# Running-App Multi-Voice Playback Switching

Status: final

## Overview

This specification defines the user-observable playback behavior for narrator-versus-character voice switching in the running app.

Issue anchors:

- GitHub issue `#20`
- GitHub issue `#23`

## Backlink

Parent specification:

- [Multi-Voice Playback Routing](multi-voice-playback-routing.md)

## Scope

This specification covers:

- audible narrator-versus-character voice switching during live playback
- boundary-aligned switching in the running app
- automatic cast assignments becoming user-observable playback differences
- graceful fallback when distinct assignments are unavailable

## Behavior

When a document contains dialogue and the resolved cast assignments produce distinct effective voices, the running app must audibly switch voices between narrator and character speech during normal playback.

The running app must not enter a silent routed-playback stall where audio stops, highlighting loops over already-spoken content, or pause/play is required to recover ordinary forward reading.

Voice changes must occur only at structural speech boundaries such as:

- narration-versus-dialogue boundaries
- dialogue span boundaries
- routed segment boundaries derived from those boundaries

The running app must not require the user to inspect diagnostics to discover whether multi-voice playback is active.

The intended effect should be directly hearable during normal playback.

When multiple compatible voices are available, automatic casting should preserve audible contrast between narrator and at least one non-narrator cast role unless the user has explicitly overridden the assignments to collapse them.

When distinct assignments are not possible because compatible voices are unavailable, the app may fall back to one voice, but that outcome must remain explicit in the surfaced cast state rather than pretending multi-voice playback is active.

## Constraints

- voice switching must be driven by the routed cast plan, not re-inferred live
- switching must not occur mid-word or mid-phoneme
- audible switching behavior must remain consistent with export and headless routed plans

## Acceptance

- a dialogue-bearing document can be played in the running app with audible narrator-versus-character voice changes when distinct assignments are available
- voice switches occur at narration or dialogue boundaries rather than arbitrary mid-utterance points
- routed playback continues forward without falling into a silent highlight loop after the first switched chunk
- if the app cannot produce distinct effective assignments, that limitation remains visible instead of silently pretending the feature is active
