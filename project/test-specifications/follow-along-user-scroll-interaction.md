# Test Specification: Follow-Along User Scroll Interaction

Status: final

## Overview

This test specification defines verification for how follow-along yields to manual scrolling and exposes recentering.

## Backlink

Feature specification:

- [Follow-Along User Scroll Interaction](../specifications/follow-along-user-scroll-interaction.md)

## Manual Smoke Check

1. Start playback and let the reader auto-follow.
2. Manually scroll away from the active spoken region.
3. Confirm auto-follow yields, a recenter control appears, and recentering returns the viewport to the spoken region.

## Automated Smoke Tests

- Drive the reader into an active follow state and verify scrolling away disables automatic recentering temporarily.
- Verify the recenter affordance appears only when the viewport has yielded away from the active spoken region.
- Verify invoking recenter restores follow state cleanly.

## Automated Acceptance Tests

- Verify user scrolling takes precedence over automatic follow until the user recenters or playback state resets the follow contract.
- Verify the active spoken region remains highlighted even while the viewport is yielded away.
- Verify recentering returns the viewport close enough to the active spoken region to resume readable follow-along.
- Verify repeated user scroll and recenter cycles do not leave the reader in a stuck half-follow state.

## Notes

- Widget tests should use scroll controllers and fake progress updates rather than real timed playback.
