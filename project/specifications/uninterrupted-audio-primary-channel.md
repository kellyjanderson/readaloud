# Uninterrupted Audio Primary Channel

Last updated: April 8, 2026
Status: Final specification

## Overview

This specification defines the ownership rule that active speech audio is the authoritative playback channel for a session.

## Backlink

Parent specification:

- [Audio-Authoritative Playback Synchronization](audio-authoritative-playback-synchronization.md)

## Scope

This specification covers:

- session-clock authority during active playback
- the boundary between audio transport ownership and follower concerns
- which events are allowed to reconfigure active playback

## Behavior

While a playback session is active:

- speech audio owns the authoritative session clock
- progress mapping follows that audio position
- highlighting, reading focus, diagnostics, and resume persistence follow mapped progress

The following may create, replace, or deliberately reconfigure the active playback session:

- `play` from `idle`
- `play` from `completed`
- `pause`
- jump actions
- voice changes
- rate changes
- document replacement
- explicit playback failure handling after audio is no longer available

The following must not stop, rebuild, or restart active playback:

- ordinary progress-event handling
- highlight derivation
- reading-focus follow behavior
- scroll-yield behavior
- diagnostics or instrumentation writes
- resume-state persistence

If a follower concern cannot keep pace, audio continues and follower recovery policy handles the resulting lag.

## Constraints

- active audio position is the canonical source of current spoken location
- follower concerns may observe audio state but do not co-own transport state
- ordinary follower load must not be treated as a transport conflict

## Acceptance

- the playback system defines one authoritative active-audio channel for a session
- ordinary progress, highlight, focus, and persistence paths are explicitly downstream of audio rather than peers of it
- implementation work from this leaf makes it impossible for follower concerns to interrupt active speech audio by default
