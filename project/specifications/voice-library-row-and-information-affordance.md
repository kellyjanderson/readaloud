# Voice Library Row and Information Affordance

Status: final

## Overview

This specification defines the primary row presentation and information affordance for voices in the library surface.

Issue anchor:

- GitHub issue `#41`

## Backlink

Parent specification:

- [Voice Library and Cast Management UI](voice-library-and-cast-management-ui.md)

## Scope

This specification covers:

- primary row information hierarchy
- direct preview affordance for voice comparison
- direct quality surfacing
- direct gender surfacing
- short description surfacing when available
- information affordance behavior across desktop and mobile

## Behavior

Each voice row should present information in this order:

1. name
2. quality rank when known
3. gender when known
4. locale
5. preview action
6. install or availability state
7. short description when available
8. short traits or description when requested

When quality metadata exists, the quality indicator must appear directly in the primary row.

When gender metadata exists, it must also appear directly in the primary row.

Each voice row must expose an explicit preview affordance so the user can hear a short sample without first committing to that voice.

If a short description exists, the row should show a compact visible summary rather than hiding all description text behind an information affordance.

When traits or description metadata exists, the row must expose an information affordance:

- desktop: hover or click
- mobile: tap

The information affordance should reveal:

- short traits
- optional prose description
- optional supporting metadata such as training-duration class

If no description exists, the UI may show traits only or omit the affordance when there is nothing meaningful to reveal.

Metadata positions within the primary row must remain spatially stable across rows even when some metadata is absent.

That means missing quality or gender data should not cause adjacent controls like preview or the remaining metadata to slide horizontally into a different slot.

The same stability rule also applies to the row's supporting information region.

Missing description or support text should not cause the row height to collapse unpredictably or pull action controls into a noticeably different vertical relationship from one row to the next.

If a short description is unavailable, the row should preserve that supporting slot with a stable fallback or equally stable reserved treatment rather than silently removing the region and changing the row structure.

## Constraints

- the user should not need to open a details surface just to learn that one voice is materially higher quality than another
- the user should not need to assign a voice just to hear what it sounds like
- the row must remain usable when metadata is partial or absent
- the row must preserve stable scan positions even when metadata is partial or absent
- missing summary data must not cause the row height or supporting-text slot to jitter between rows

## Acceptance

- the voice library can show quality directly in the row when known
- the voice library can show gender directly in the row when known
- each voice row includes a preview action
- a short description is visible in the row when available
- richer metadata can be inspected without cluttering the main row
- quality, gender, preview, and primary action positions remain visually stable across rows even when metadata is missing
- summary text or its reserved slot remains vertically stable across rows even when descriptions are absent
- desktop and mobile interaction behavior are both defined
