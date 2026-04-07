# Test Specification: Quoted Dialogue Voice Segmentation

Status: final

## Overview

This test specification defines verification for keeping quoted spoken content in character voice while unquoted speaker tags and narration stay in narrator voice.

## Backlink

Feature specification:

- [Quoted Dialogue Voice Segmentation](../specifications/quoted-dialogue-voice-segmentation.md)

## Manual Smoke Check

1. Load a dialogue-heavy fixture with quote-tag and quote-tag-quote paragraphs.
2. Play through examples such as `"JUST STOP FIGHTING!" Jennifer screamed, pulling on her hair.`
3. Confirm the quoted text is in the character voice and the surrounding unquoted narration stays in narrator voice.

## Automated Smoke Tests

- Import a fixture containing simple quote-tag narration and assert the routed attribution splits quoted and unquoted spans.
- Import a fixture containing quote-tag-quote exchanges in one paragraph and assert each quoted block is routed separately.
- Verify non-dialogue paragraphs remain entirely narrator-attributed.

## Automated Acceptance Tests

- Verify quoted text is always routed to a character voice or marked unknown, never silently folded into narrator-attributed dialogue.
- Verify unquoted attribution tags such as `John said` or `Jennifer screamed` remain narrator-attributed even when adjacent to dialogue.
- Verify multi-quote paragraphs produce narrator-character-narrator-character structure when the prose requires it.
- Verify the internal document attribution layer materializes these routed spans at document load rather than inventing them during playback.

## Notes

- Use durable text fixtures with exact expected routed spans so regressions are easy to spot.
