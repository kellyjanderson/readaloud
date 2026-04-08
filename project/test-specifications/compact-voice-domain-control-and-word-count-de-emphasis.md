# Compact Voice Domain Control And Word Count De-Emphasis

Paired feature specification:

- [Compact Voice Domain Control And Word Count De-Emphasis](../specifications/compact-voice-domain-control-and-word-count-de-emphasis.md)

## Manual Smoke Check

- Enable multi-voice mode and confirm the top-level Reader control presents a compact `Character Voices` entry instead of a large summary block.
- Confirm whole-document word count is no longer given prominent top-level placement.

## Automated Smoke Expectations

- widget tests verify that the Reader shell shows a compact `Character Voices` entrypoint in multi-voice mode
- widget tests verify that the old top-level whole-document word-count text is not present

## Automated Acceptance Expectations

- acceptance coverage proves the top-level Reader controls preserve a balanced hierarchy between transport and voice-domain access
- acceptance coverage proves low-value metadata such as whole-document word count is absent from the primary control row
