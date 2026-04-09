# Append-Only Forward Playback Queue

Last updated: April 8, 2026
Status: Final specification

## Overview

This specification defines how the active playback queue must behave while forward playback continues under one unchanged session identity.

## Backlink

Parent specification:

- [Audio-Authoritative Playback Synchronization](audio-authoritative-playback-synchronization.md)

## Scope

This specification covers:

- queue mutation while a session is actively playing forward
- later-chunk arrival during active playback
- the boundary between normal queue growth and true queue rebuilds

## Behavior

Once the first chunk of an active session is playing:

- later prepared chunks append behind the playhead in playback order
- ordinary later-chunk readiness must extend the queue rather than rebuilding it
- already consumed chunks may fall out of the live queue bookkeeping without disturbing future playback order

Ordinary forward playback must not use a full player-source rebuild merely because:

- a later chunk became ready
- progress mapping advanced
- highlight or follow state changed
- follower state needed to catch up

Player-source replacement or queue rebuild is allowed only when:

- session identity changes because of jump, rate, voice, replay, or document replacement
- or true starvation recovery is required after prepared audio has already been exhausted

Even in starvation recovery, the system must resume from the next unplayed audio point rather than replaying already consumed content.

## Constraints

- later chunk arrival alone is not a transport event
- forward playback order must remain monotonic within a session
- queue bookkeeping may change, but ordinary forward audio continuity must remain the priority

## Acceptance

- normal forward playback extends by appending future chunks behind active audio
- ordinary later-chunk readiness does not require `stop -> setAudioSources -> seek -> play`
- if queue rebuild is still required after true starvation, recovery resumes from the next unplayed point instead of replaying earlier audio
