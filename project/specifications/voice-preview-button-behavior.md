# Voice Preview Button Behavior

Status: final

## Overview

This specification defines the reusable preview-control behavior used anywhere the app surfaces selectable voices.

Issue anchor:

- GitHub issue `#40`

## Backlink

Parent specification:

- [Voice Library and Cast Management UI](voice-library-and-cast-management-ui.md)

## Scope

This specification covers:

- preview activation without assignment
- one-preview-at-a-time behavior
- idle, playing, and stopping states
- desktop and mobile affordance presentation

## Behavior

Any surfaced voice choice that is selectable by the user must expose a preview action that can be activated without first assigning that voice.

The preview control should support these visible states:

- idle
- playing
- stopping or loading when transition feedback is needed

Only one preview may remain active at a time within the current voice-management surface.

Starting a new preview should stop or replace the prior active preview rather than layering multiple samples.

If the Reader is currently playing or buffering ordinary reading audio, pressing preview should pause that reading session automatically before preview begins.

The app should not warn the user to pause manually when the app can perform that pause itself as part of the preview interaction.

The preview control should remain compact and icon-led.

On desktop, it may use an icon plus tooltip.

On mobile, it may remain icon-only if the touch target stays generous.

## Constraints

- preview must not require committing the current selection
- preview must not require an extra manual pause step when ordinary Reader playback can be paused automatically
- preview state must remain understandable without turning the row into a mini transport bar
- preview behavior must remain consistent between voice-library rows and cast-assignment rows

## Acceptance

- a surfaced voice can be previewed without assignment
- an active reading session is paused automatically when needed so preview can begin directly
- only one preview remains active at a time in the current surface
- the preview control has defined idle and active behavior
- desktop and mobile presentation rules are defined
