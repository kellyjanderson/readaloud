# Compact Voice Domain Control And Word Count De-Emphasis

Status: final

## Overview

This specification defines the compact top-level treatment for voice-domain access on the Reader surface and removes low-value metadata such as whole-document word count from prominent top-level placement.

Issue anchor:

- GitHub issue `#37`

## Backlink

Parent specification:

- [Primary Reader Surface UI](primary-reader-surface-ui.md)

## Scope

This specification covers:

- the top-level `Character Voices` entry when multi-voice mode is enabled
- the visual weight and size of that entry
- de-emphasis or removal of whole-document word count from the primary control row

## Behavior

When multi-voice mode is enabled, the top-level voice-domain control should be a compact `Character Voices` entrypoint rather than a large summary card competing with reading controls.

The primary-surface control should:

- read clearly as an action that opens voice assignment management
- avoid verbose narrator or cast summary text unless that text is immediately useful at the moment of interaction
- feel visually balanced with the transport capsule rather than outweighing it

If the primary surface has room for only one compact voice-domain affordance, that affordance should be the `Character Voices` button itself.

Whole-document word count should not occupy top-level reader chrome unless a later specification promotes it for a concrete reader need. For the current Reader shell, whole-document word count should be removed or moved to a secondary information surface.

## Constraints

- top-level controls must preserve a reading-first hierarchy
- voice-domain entry must remain obviously tappable and accessible
- low-value metadata must not be given stronger top-level emphasis than playback or reading controls

## Acceptance

- the running app presents a compact top-level `Character Voices` entry when multi-voice mode is enabled
- the top-level control no longer reads like a large summary card when it only functions as an entrypoint
- whole-document word count is no longer given prominent top-level placement beside the primary reading controls
