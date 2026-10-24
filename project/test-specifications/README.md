# Retained verification scenarios

Existing detailed test specifications remain reference material. New work defines acceptance in the ACD and bounded checks in its plan; creating one test document per feature leaf is no longer required. Existing checked/final labels are not fresh test evidence. See [AGENTS.md](../../AGENTS.md).

## Current Documents

### Document Preparation and Buffered Playback

- [Prepared Document and Buffered Playback](prepared-document-and-buffered-playback.md)

### App Shell And Platform Navigation

- [Desktop Native Menu And Mobile Overflow Navigation](desktop-native-menu-and-mobile-overflow-navigation.md)
- [Mobile Overflow Menu Domain Grouping](mobile-overflow-menu-domain-grouping.md)
- [Desktop Reader Title Chrome Minimization](desktop-reader-title-chrome-minimization.md)
- [Reader-Only App Shell Until Authoring Exists](studio-workspace-entry-and-reader-isolation.md)

### Visual Design System Adoption

- [App-Wide Semantic Theme Token Adoption](app-wide-semantic-theme-token-adoption.md)
- [Editorial Typography Role Application](editorial-typography-role-application.md)
- [Secondary Surface Component Family Consistency](secondary-surface-component-family-consistency.md)
- [Reader Options Sectioned Information Hierarchy](reader-options-sectioned-information-hierarchy.md)

### Reader Surface And Voice Management

- [Segmented Transport Capsule](segmented-transport-capsule.md)
- [Primary Reader Control Set](primary-reader-control-set.md)
- [Document Identity Outside Reading Surface](document-identity-outside-reading-surface.md)
- [Integrated Secondary Voice Access](integrated-secondary-voice-access.md)
- [Document-Load Cast Processing Overlay](document-load-cast-processing-overlay.md)
- [Multi-Voice Mode Toggle And Cast Entrypoint](multi-voice-mode-toggle-and-cast-entrypoint.md)
- [Feedback Surface Contrast Readability](feedback-surface-contrast-readability.md)
- [Transient Feedback Toast Behavior](transient-feedback-toast-behavior.md)
- [Compact Voice Domain Control And Word Count De-Emphasis](compact-voice-domain-control-and-word-count-de-emphasis.md)
- [Reader Preferences Controls](reader-preferences-controls.md)
- [Sleep Timer And Timing Surface](sleep-timer-and-timing-surface.md)
- [Reader Diagnostics And Source Panels](reader-diagnostics-and-source-panels.md)
- [Voice Library Row And Information Affordance](voice-library-row-and-information-affordance.md)
- [Voice Library Direct Character Assignment](voice-library-direct-character-assignment.md)
- [Voice Preview Button Behavior](voice-preview-button-behavior.md)
- [Cast Management Dialog Structure](cast-management-dialog-structure.md)
- [Voice Management Dialog Contrast And Readability](voice-management-dialog-contrast-and-readability.md)
- [Appearance Mode Selection And System Following](appearance-mode-selection-and-system-following.md)
- [Spoken Highlight Visual Presentation](spoken-highlight-visual-presentation.md)
- [Reading Surface Contrast And Highlight Legibility](reading-surface-contrast-and-highlight-legibility.md)
- [Follow-Along User Scroll Interaction](follow-along-user-scroll-interaction.md)

### Multi-Voice Playback

- [Cast Voice Override Workflow](cast-voice-override-workflow.md)
- [US-English Starter Voice Set And Auto-Cast Preference](us-english-starter-voice-set-and-auto-cast-preference.md)
- [Document-Specific Cast Voice Assignment Memory](document-specific-cast-voice-assignment-memory.md)
- [Quoted Dialogue Voice Segmentation](quoted-dialogue-voice-segmentation.md)
- [Running-App Multi-Voice Playback Switching](running-app-multi-voice-playback-switching.md)

### Playback Coordination And Follower Synchronization

- [Playback Coordination](playback-coordination.md)
- [Uninterrupted Audio Primary Channel](uninterrupted-audio-primary-channel.md)
- [Append-Only Forward Playback Queue](append-only-forward-playback-queue.md)
- [Buffered Lead-Time And Underrun Policy](buffered-lead-time-and-underrun-policy.md)
- [Running-App Uninterrupted Speech Under Follow-Along Load](running-app-uninterrupted-speech-under-follow-along-load.md)
- [Playback Progress And Jump Mapping](playback-progress-and-jump-mapping.md)
- [Document Replacement Playback Reset And Stale Event Rejection](document-replacement-playback-reset-and-stale-event-rejection.md)
- [Follower Progress Coalescing And Drift Resynchronization](follower-progress-coalescing-and-drift-resynchronization.md)

### Reader Session And Live Input

- [File-Backed Document Restore And Directory Continuity](file-backed-document-restore-and-directory-continuity.md)
- [Persistent Folder Access For Startup Restore](persistent-file-access-for-startup-restore.md)
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
