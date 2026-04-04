# Release 0.3.0

Status: planning

## Intent

`0.3.0` is intended to move `Read Aloud` from a strong single-voice reader into a more story-aware and visually trackable reading experience.

The release is centered on three product goals:

- detect dialogue and introduce narrator-versus-character voice assignment
- highlight and advance the text currently being spoken
- make voice selection more informed by surfacing voice quality and descriptive metadata where available

This release should improve both:

- story readability and listening immersion
- the user’s ability to understand and manage voice choices

## Planned Architecture

- [Speech Enrichment and Narration](../architecture/speech-enrichment-and-narration.md)
- [Character Dialogue Attribution and Voice Casting](../architecture/character-dialogue-attribution-and-voice-casting.md)
- [Playback Orchestration and Synthesis Boundaries](../architecture/playback-orchestration-and-synthesis-boundaries.md)
- [Spoken Text Highlighting and Reading Focus](../architecture/spoken-text-highlighting-and-reading-focus.md)

## Planned UI Definitions

- [Primary Surface and Complexity Layering](../ui/primary-surface-and-complexity-layering.md)
- [Voice Library and Cast Management](../ui/voice-library-and-cast-management.md)
- [Follow-Along Reading Surface](../ui/follow-along-reading-surface.md)

## Planned Specifications

- [Dialogue Span and Speaker Attribution](../specifications/dialogue-span-and-speaker-attribution.md)
- [Character Cast Registry and Voice Assignment](../specifications/character-cast-registry-and-voice-assignment.md)
- [Multi-Voice Playback Routing](../specifications/multi-voice-playback-routing.md)
- [Spoken Text Highlighting and Reading Focus](../specifications/spoken-text-highlighting-and-reading-focus.md)
- [Voice Library Metadata and Information Surfacing](../specifications/voice-library-metadata-and-information-surfacing.md)
- [Voice Library and Cast Management UI](../specifications/voice-library-and-cast-management-ui.md)
- [Follow-Along Reading Surface UI](../specifications/follow-along-reading-surface-ui.md)

## Notes

- This release document is the holistic release definition for `0.3.0`.
- Release documents are stored at `project/release-x.y.z/README.md`.
- A release document should describe the version intent and link the architecture, UI definitions, and specifications planned for that version.
