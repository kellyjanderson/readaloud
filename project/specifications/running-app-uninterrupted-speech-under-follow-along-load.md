# Running-App Uninterrupted Speech Under Follow-Along Load

Last updated: April 8, 2026
Status: Final specification

## Overview

This specification defines the user-observable outcome of the audio-authoritative rearchitecture during ordinary running-app playback.

## Backlink

Parent specification:

- [Audio-Authoritative Playback Synchronization](audio-authoritative-playback-synchronization.md)

## Scope

This specification covers:

- live playback with spoken highlighting active
- playback while the reader surface follows or catches up
- ordinary later-chunk arrival during long-form reading

## Behavior

In the running app, ordinary reading with active follow-along must preserve audible speech continuity as the primary experience.

During active playback:

- speech must continue smoothly while highlighting and follow-along update
- if the visible reader surface falls behind, it may skip intermediate states and catch up to the current spoken region
- visible catch-up may appear as a jump to the current audio position when needed

The system must not prefer preserving every intermediate highlight step over preserving audible continuity.

Ordinary follow-along load must not create:

- repeated audible stutter caused by coordination between text and audio
- silent highlight-only loops over already spoken content
- a required user pause/play intervention to keep speech moving

## Constraints

- this is a surfaced running-app behavior, not only an internal queue rule
- acceptance must be satisfied by the observed app experience rather than by isolated controller state alone

## Acceptance

- with follow-along active during ordinary long-form playback, speech remains audibly continuous while visible text remains reasonably aligned
- if the reader surface cannot keep up, the visible spoken region catches up by skipping or jumping forward rather than by making speech stutter
- the running app no longer requires manual intervention to continue ordinary playback after text-side coordination pressure
