# Reading Focus Follow Policy

Status: final

## Overview

This specification defines how the reader viewport follows playback without fighting the user.

## Backlink

Parent specification:

- [Spoken Text Highlighting and Reading Focus](spoken-text-highlighting-and-reading-focus.md)

## Scope

This specification covers:

- automatic follow behavior
- pause and resume semantics
- user scroll yield behavior
- re-centering policy

## Behavior

Viewport follow behavior must:

- keep the active reading region visible during playback
- avoid per-word recenter jitter
- stop auto-following when playback is paused
- resume according to explicit follow policy when playback resumes

If the user manually scrolls while playback is running, the viewport must temporarily yield control and must not snap back immediately.

The system may provide a simple way to re-center on the active spoken range.

## Constraints

- follow policy must remain separate from spoken selection derivation
- viewport motion must favor reading stability over maximum movement frequency

## Acceptance

- the reader viewport follows playback without jitter
- manual scrolling does not trigger immediate snapback
- pause and resume behavior are explicit and stable
