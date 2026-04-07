# Multi-Voice Mode Toggle And Cast Entrypoint

Status: final

## Overview

This specification defines how the user turns multi-voice mode on or off and how the primary-surface voice control changes when that mode is active.

Issue anchor:

- GitHub issue `#19`

## Backlink

Parent specification:

- [Primary Reader Surface UI](primary-reader-surface-ui.md)

## Scope

This specification covers:

- the user-visible on or off switch for multi-voice mode
- narrator-as-main-voice behavior
- primary-surface substitution of the old single-voice control with cast management access

## Behavior

The app must provide an explicit user control that turns multi-voice mode on or off.

When multi-voice mode is off:

- the app may behave like the simpler single-voice reader
- the primary surface may show the ordinary active voice selector

When multi-voice mode is on:

- the selected main voice represents the narrator
- the primary-surface voice entry must shift from a misleading whole-document voice selector to a cast-management entry such as `Character Voices`
- narrator and character voice management must remain accessible from that entry path

## Constraints

- the top-level control must clearly communicate which reading mode is active
- the primary surface must not pretend that one voice controls the whole document when multi-voice mode is enabled
- cast management must remain accessible without flooding the primary surface with every voice option

## Acceptance

- the user can explicitly enable or disable multi-voice mode
- when multi-voice mode is on, the primary voice entry reflects narrator-plus-cast management instead of whole-document single-voice control
- when multi-voice mode is off, the simpler single-voice surface remains available
