# Voice Library Row and Information Affordance

Status: final

## Overview

This specification defines the primary row presentation and information affordance for voices in the library surface.

## Backlink

Parent specification:

- [Voice Library and Cast Management UI](voice-library-and-cast-management-ui.md)

## Scope

This specification covers:

- primary row information hierarchy
- direct quality surfacing
- information affordance behavior across desktop and mobile

## Behavior

Each voice row should present information in this order:

1. name
2. locale
3. quality indicator when known
4. install state
5. short traits or description when requested

When quality metadata exists, the quality indicator must appear directly in the primary row.

When traits or description metadata exists, the row must expose an information affordance:

- desktop: hover or click
- mobile: tap

The information affordance should reveal:

- short traits
- optional prose description
- optional supporting metadata such as training-duration class

If no description exists, the UI may show traits only or omit the affordance when there is nothing meaningful to reveal.

## Constraints

- the user should not need to open a details surface just to learn that one voice is materially higher quality than another
- the row must remain usable when metadata is partial or absent

## Acceptance

- the voice library can show quality directly in the row when known
- richer metadata can be inspected without cluttering the main row
- desktop and mobile interaction behavior are both defined
