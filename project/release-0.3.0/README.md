# Release 0.3.0

Status: fully specified, implementation active

## Intent

`0.3.0` is intended to move `Read Aloud` from a strong single-voice reader into a more story-aware and visually trackable reading experience.

The release is centered on three product goals:

- detect dialogue and introduce narrator-versus-character voice assignment
- highlight and advance the text currently being spoken
- make voice selection more informed by surfacing voice quality and descriptive metadata where available

This release also includes the UI cleanup needed to make those features feel coherent:

- simplify the primary reading surface
- move advanced controls into secondary UI and menus
- support light, dark, and follow-system appearance modes
- make live file input behave like a truly live reading workflow
- preserve continuity by reopening the most recent file-backed document at the user's last heard position

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
- [Reader Options and Secondary Settings](../ui/reader-options-and-secondary-settings.md)
- [Theme and Appearance Modes](../ui/theme-and-appearance-modes.md)
- [Live Input and File Menu Behavior](../ui/live-input-and-file-menu-behavior.md)

## Planned Specifications

- [Dialogue Span and Speaker Attribution](../specifications/dialogue-span-and-speaker-attribution.md)
- [Character Cast Registry and Voice Assignment](../specifications/character-cast-registry-and-voice-assignment.md)
- [Multi-Voice Playback Routing](../specifications/multi-voice-playback-routing.md)
- [Spoken Text Highlighting and Reading Focus](../specifications/spoken-text-highlighting-and-reading-focus.md)
- [Voice Library Metadata and Information Surfacing](../specifications/voice-library-metadata-and-information-surfacing.md)
- [Primary Reader Surface UI](../specifications/primary-reader-surface-ui.md)
- [Reader Options And Secondary Settings UI](../specifications/reader-options-and-secondary-settings-ui.md)
- [Voice Library and Cast Management UI](../specifications/voice-library-and-cast-management-ui.md)
- [Follow-Along Reading Surface UI](../specifications/follow-along-reading-surface-ui.md)
- [Theme and Appearance Modes UI](../specifications/theme-and-appearance-modes-ui.md)
- [Live Input and File Menu UI](../specifications/live-input-and-file-menu-ui.md)

## Notes

- This release document is the holistic release definition for `0.3.0`.
- Release documents are stored at `project/release-x.y.z/README.md`.
- A release document should describe the version intent and link the architecture, UI definitions, and specifications planned for that version.
- Support and enabling leaves may land before the full release experience is visible.
- the `0.3.0` feature set is now fully represented by architecture, UI definitions, and final leaf specifications
- the currently implemented working branch now surfaces narrator-versus-character switching, follow-along reading, primary-surface cleanup, appearance modes, live-input continuation semantics, and remembered reading position
- release completion still depends on integration, verification, and landing, not on missing specification coverage
