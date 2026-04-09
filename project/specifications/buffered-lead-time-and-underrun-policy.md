# Buffered Lead-Time And Underrun Policy

Last updated: April 8, 2026
Status: Final specification

## Overview

This specification defines the buffer-lead policy that keeps active speech audio ahead of follower work and defines what a real underrun means.

## Backlink

Parent specification:

- [Audio-Authoritative Playback Synchronization](audio-authoritative-playback-synchronization.md)

## Scope

This specification covers:

- buffered lead-time measurement
- startup playback warmup before first audible speech
- scheduler reaction to shrinking lead time
- the difference between follower lag and true audio starvation
- underrun recovery semantics

## Behavior

The playback system must maintain an explicit estimate of buffered audio lead time ahead of the current playhead.

Initial operating thresholds:

- target buffered lead time: `8` seconds
- low-water threshold: `4` seconds
- critical threshold: `2` seconds

When a session is about to start playback and future chunks are still expected:

- the system must prefer a short startup warmup over starting audible speech with only a fragile first chunk buffered
- startup may wait for additional prepared audio before the first `play`
- startup is warm enough once either:
  - enough buffered lead exists to meet the startup runway threshold
  - or multiple future chunks are already buffered with at least low-water lead
  - or no further future work remains for that session

Startup warmup exists to reduce first-paragraph stutter and early queue starvation.

When lead time falls below the low-water threshold:

- next-chunk preparation gains highest ordinary scheduling priority
- instrumentation records the reduced lead time
- follower behavior remains best-effort and must not steal control from the audio rail

When lead time falls below the critical threshold:

- the system treats future audio continuity as the dominant scheduling concern
- nonessential follower catch-up work may be coalesced or skipped

A true underrun exists only when active playback runs out of prepared audio.

The following are not underruns:

- highlight lag
- reading-focus lag
- delayed resume persistence
- delayed diagnostics updates

When a true underrun occurs:

- the system may surface buffering state
- the system must not emit silent progress or highlight loops over already spoken content
- recovery resumes from the next unplayed audio point once enough audio exists again
- follower state resynchronizes to recovered audio rather than trying to replay missed visual steps

## Constraints

- lead-time policy must be observable through instrumentation
- follower lag must not be misclassified as audio starvation
- ordinary scheduler behavior must prefer preserving buffered audio over preserving every intermediate visual state

## Acceptance

- buffered lead time has explicit target, low-water, and critical thresholds
- scheduler behavior is defined for shrinking lead time
- startup playback waits for a real initial runway when future chunks are still being prepared
- real underruns are distinguished from UI lag
- underrun recovery no longer permits silent highlight-only catch-up as a valid mode
