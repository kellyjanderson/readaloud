# Test Specifications Index

Test specifications define how final feature leaf specifications should be verified manually and automatically.

Each document in this folder should pair to exactly one final feature leaf specification in:

```text
project/specifications/
```

The paired filename should normally use the same basename as the feature specification it verifies.

This initial backfill focuses on the current running-app feature surface so active UI and playback work can be tested against durable expectations instead of ad hoc notes.

## Current Documents

### Reader Surface And Voice Management

- [Primary Reader Control Set](primary-reader-control-set.md)
- [Document Identity Outside Reading Surface](document-identity-outside-reading-surface.md)
- [Integrated Secondary Voice Access](integrated-secondary-voice-access.md)
- [Document-Load Cast Processing Overlay](document-load-cast-processing-overlay.md)
- [Multi-Voice Mode Toggle And Cast Entrypoint](multi-voice-mode-toggle-and-cast-entrypoint.md)
- [Feedback Surface Contrast Readability](feedback-surface-contrast-readability.md)
- [Reader Preferences Controls](reader-preferences-controls.md)
- [Sleep Timer And Timing Surface](sleep-timer-and-timing-surface.md)
- [Reader Diagnostics And Source Panels](reader-diagnostics-and-source-panels.md)
- [Voice Library Row And Information Affordance](voice-library-row-and-information-affordance.md)
- [Cast Management Dialog Structure](cast-management-dialog-structure.md)
- [Voice Management Dialog Contrast And Readability](voice-management-dialog-contrast-and-readability.md)
- [Appearance Mode Selection And System Following](appearance-mode-selection-and-system-following.md)
- [Spoken Highlight Visual Presentation](spoken-highlight-visual-presentation.md)
- [Reading Surface Contrast And Highlight Legibility](reading-surface-contrast-and-highlight-legibility.md)
- [Follow-Along User Scroll Interaction](follow-along-user-scroll-interaction.md)

### Multi-Voice Playback

- [Cast Voice Override Workflow](cast-voice-override-workflow.md)
- [Quoted Dialogue Voice Segmentation](quoted-dialogue-voice-segmentation.md)
- [Running-App Multi-Voice Playback Switching](running-app-multi-voice-playback-switching.md)
- [Playback Coordination](playback-coordination.md)
- [Playback Progress And Jump Mapping](playback-progress-and-jump-mapping.md)

### Reader Session And Live Input

- [File-Backed Document Restore And Directory Continuity](file-backed-document-restore-and-directory-continuity.md)
- [Remembered Reading Position And Startup Resume](remembered-reading-position-and-startup-resume.md)
- [Watched-File Session Refresh](watched-file-session-refresh.md)
- [Live Input Menu Placement And Playing-State Continuation](live-input-menu-placement-and-playing-state-continuation.md)

## Structure

Each test specification should include:

- a backlink to the paired feature specification
- a short manual smoke check
- automated smoke expectations
- automated acceptance expectations

Manual guidance may stay short.

Automated smoke and acceptance guidance should be the heavier part of the document.
