# Document Replacement Playback Reset And Stale Event Rejection

Paired feature specification:

- [Document Replacement Playback Reset And Stale Event Rejection](../specifications/document-replacement-playback-reset-and-stale-event-rejection.md)

## Manual Smoke Check

- Start playback on one document, then open a different document while the first is buffering or playing.
- Confirm the new document does not echo, double-play, or inherit erratic highlight movement from the prior one.

## Automated Smoke Expectations

- controller tests cover replacing the active document while prior progress events still arrive
- stale prior-document progress events are ignored when their document identity no longer matches the active document
- replacing a document resets playback-facing state needed for selection and highlight behavior

## Automated Acceptance Expectations

- an acceptance test simulates playback progress from document A, replaces the document with document B, and proves that later document-A progress cannot move document-B highlight state
- an acceptance test proves that replacing a restored document with a newly opened document does not leave the new document in duplicated or stale playback state
- regression coverage proves that playback state after document replacement reflects only the active document
