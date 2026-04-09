# Test Specification: Buffered Lead-Time And Underrun Policy

Status: final

## Overview

This test specification defines verification for buffered lead-time thresholds, scheduler priority shifts, and true underrun handling.

## Backlink

Feature specification:

- [Buffered Lead-Time And Underrun Policy](../specifications/buffered-lead-time-and-underrun-policy.md)

## Manual Smoke Check

1. Read a long document with ordinary follow-along active.
2. Confirm the app may briefly show buffering only when audio is actually short, not merely when text catches up.
3. Confirm any recovery resumes from the next unheard position instead of looping silent highlights.

## Automated Smoke Tests

- Feed queue snapshots with varying buffered lead times and verify low-water and critical policy transitions.
- Verify startup playback waits for a warm enough initial runway when future chunks are still pending.
- Verify follower lag does not classify as an underrun.
- Verify true starvation emits buffering semantics rather than silent highlight-only progression.

## Automated Acceptance Tests

- Verify startup does not begin audible playback with only one fragile chunk buffered when more chunks are still pending.
- Verify startup may proceed once low-water runway with multiple buffered chunks exists, or once no future work remains.
- Verify scheduler priority increases when lead time drops below the configured low-water threshold.
- Verify critical lead-time handling favors preserving future audio over preserving every intermediate follower update.
- Verify underrun recovery resumes from the next unplayed point and resynchronizes the follower path to that recovered audio position.

## Notes

- Metric and instrumentation assertions should be part of this leaf, not only transport-state assertions.
