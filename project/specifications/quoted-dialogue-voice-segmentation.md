# Quoted Dialogue Voice Segmentation

Status: final

## Overview

This specification defines how quoted dialogue and surrounding narration must be separated for narrator-versus-character voice routing.

Issue anchor:

- GitHub issue `#17`
- GitHub issue `#23`

## Backlink

Parent specification:

- [Multi-Voice Playback Routing](multi-voice-playback-routing.md)

## Scope

This specification covers:

- character voice application to quoted dialogue only
- narrator treatment of unquoted speaker tags
- narrator treatment of surrounding narration
- structural routing boundaries required to make that distinction audible

## Behavior

In prose dialogue, the quoted spoken content is the portion that should be routed to the speaking character's voice.

Unquoted text must remain in the narrator voice, including:

- speaker tags such as `John said,`
- surrounding narration before the quote
- surrounding narration after the quote

For example:

- `John said, "Are you ok?"`
  - `John said,` -> narrator voice
  - `"Are you ok?"` -> John's voice

- `"Are you ok?" John asked.`
  - `"Are you ok?"` -> John's voice
  - `John asked.` -> narrator voice

The routing layer must split mixed dialogue-and-tag sentences at the quotation boundary so the running app can audibly preserve narrator-versus-character distinction inside one sentence.

This rule also applies across short alternating dialogue exchanges in one paragraph.

For example:

- `"John, why did you have to budge in front of me this morning?" Elliot said`
  - quoted text -> Elliot's voice
  - `Elliot said` -> narrator voice
- `"I dunno. I thought taking someone's position in line is how we operate now," John replied sarcastically.`
  - quoted text -> John's voice
  - `John replied sarcastically.` -> narrator voice

When distinct voice assignments are available, the narrator voice should remain audibly distinct from at least one non-narrator character voice.

## Constraints

- the system must not treat an entire mixed sentence as character speech solely because a speaker was attributed to the quoted portion
- routing must remain boundary-aligned and must not switch voices mid-word
- the same quoted-dialogue segmentation must be reusable by playback, export, and headless synthesis

## Acceptance

- in mixed dialogue sentences, only the quoted spoken content is routed to the character voice
- unquoted speaker tags and surrounding narration stay in the narrator voice
- consecutive quote-tag exchanges in one paragraph preserve narrator tags between character-spoken quotes
- the distinction is directly hearable in the running app during normal playback
- routed diagnostics remain consistent with the quoted-versus-unquoted split
