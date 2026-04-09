# Audio-Authoritative Playback Synchronization

Last updated: April 8, 2026
Status: Draft specification

## Overview

This specification defines the focused rearchitecture work needed to make active speech audio the authoritative playback channel while progress mapping and reader presentation follow behind it.

## Backlink

Parent specification:

- [Imported Document Playback](imported-document-playback.md)

## Scope

This specification covers:

- audio-session authority during active playback
- forward queue mutation rules while a session is playing
- buffered lead-time and underrun policy
- the surfaced running-app expectation that follow-along must not make speech stutter

## Behavior

This parent branch now delegates detailed implementation to child specifications.

In particular:

- uninterrupted audio authority belongs to its own leaf
- append-only forward queue behavior belongs to its own leaf
- buffered lead-time and underrun policy belong to their own leaf
- the observable running-app outcome belongs to its own surfaced leaf

This parent specification keeps only the branch-level contract that active speech audio is the authoritative real-time rail, while progress mapping and reader presentation are follower channels that may lag, coalesce, or resynchronize without interrupting audio.

## Constraints

- active speech audio owns the session clock while playback is running
- non-transport follower behavior must not stop, rebuild, or restart active playback
- ordinary forward queue growth must preserve monotonic playback order
- if follower state falls behind, the system must prefer visible catch-up over audible interruption

## Refinement Status

Refinement complete for the current planned branch.

## Child Specifications

- [Uninterrupted Audio Primary Channel](uninterrupted-audio-primary-channel.md)
- [Append-Only Forward Playback Queue](append-only-forward-playback-queue.md)
- [Buffered Lead-Time And Underrun Policy](buffered-lead-time-and-underrun-policy.md)
- [Running-App Uninterrupted Speech Under Follow-Along Load](running-app-uninterrupted-speech-under-follow-along-load.md)

## Acceptance

- imported playback explicitly represents audio-authoritative coordination work rather than leaving it implied inside broad transport behavior
- the remaining work in this branch is represented by final leaf specifications
