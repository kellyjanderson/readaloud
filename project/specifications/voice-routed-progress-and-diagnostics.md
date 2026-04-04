# Voice-Routed Progress and Diagnostics

Status: final

## Overview

This specification defines how multi-voice routing remains visible through progress events and runtime diagnostics.

## Backlink

Parent specification:

- [Multi-Voice Playback Routing](multi-voice-playback-routing.md)

## Scope

This specification covers:

- progress payload requirements for routed playback
- debug trace visibility for routed voices
- route-aware diagnostics

## Behavior

When multi-voice routing is active, progress and diagnostics must expose enough information to determine:

- which voice was active for the spoken range
- which routed span or cast context produced that voice choice

Progress payloads must continue to include:

- normalized speech ids and ranges
- active voice id

Runtime diagnostics and trace output must make routed voice use inspectable during:

- live playback
- export
- headless synthesis

## Constraints

- routed diagnostics must remain compatible with existing progress mapping
- diagnostics must not require reparsing raw synthesis input to understand voice switches

## Acceptance

- the app can inspect which voice was used for a spoken range
- routed playback remains debuggable through existing progress and trace channels
- export and headless runs expose the same routed voice truth as live playback
