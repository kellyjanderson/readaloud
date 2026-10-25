# Documentation archive

Historical context only. Current facts live in [architecture](../architecture/README.md); proposed changes live in [ACDs](../acd/README.md). Nothing here is an active work order or proof of implementation.

## Architecture snapshots

[October 24 pre-reconciliation index](architecture/2026-10-24/README.md) preserves all earlier prose, including accepted targets and stale completion claims. It must not be loaded as current authority.

## Archived specification ancestors

The following 19 documents explicitly delegated their behavior to children, declared refinement complete, and had final terminal descendants. Their full text is retained. Children now link directly to architecture; old links point here only for provenance. This is contract refinement coverage, not evidence that those children are implemented.

### [app shell and platform navigation ui](specification-ancestors/app-shell-and-platform-navigation-ui.md)

- [Desktop Native Menu And Mobile Overflow Navigation](../specifications/desktop-native-menu-and-mobile-overflow-navigation.md)
- [Mobile Overflow Menu Domain Grouping](../specifications/mobile-overflow-menu-domain-grouping.md)
- [Desktop Reader Title Chrome Minimization](../specifications/desktop-reader-title-chrome-minimization.md)
- [Reader-Only App Shell Until Authoring Exists](../specifications/studio-workspace-entry-and-reader-isolation.md)

### [audio authoritative playback synchronization](specification-ancestors/audio-authoritative-playback-synchronization.md)

- [Uninterrupted Audio Primary Channel](../specifications/uninterrupted-audio-primary-channel.md)
- [Append-Only Forward Playback Queue](../specifications/append-only-forward-playback-queue.md)
- [Buffered Lead-Time And Underrun Policy](../specifications/buffered-lead-time-and-underrun-policy.md)
- [Running-App Uninterrupted Speech Under Follow-Along Load](../specifications/running-app-uninterrupted-speech-under-follow-along-load.md)

### [audio export and headless execution](specification-ancestors/audio-export-and-headless-execution.md)

- [Audio Export Assembly](../specifications/audio-export-assembly.md)
- [Command-Line Mode Selection](../specifications/command-line-mode-selection.md)
- [Headless Synthesis Session](../specifications/headless-synthesis-session.md)
- [In-App Audio Export Workflow](../specifications/in-app-audio-export-workflow.md)
- [Speech QA Debug Tooling](../specifications/speech-qa-debug-tooling.md)

### [character cast registry and voice assignment](specification-ancestors/character-cast-registry-and-voice-assignment.md)

- [Character Cast Registry Model](../specifications/character-cast-registry-model.md)
- [Character Reference Consolidation And Alias Clustering](../specifications/character-reference-consolidation-and-alias-clustering.md)
- [Character Gender Identity Extraction](specification-ancestors/character-gender-identity-extraction.md)
- [Automatic Voice Casting and Override Resolution](../specifications/automatic-voice-casting-and-override-resolution.md)
- [Context-Aware Automatic Voice Casting](../specifications/context-aware-automatic-voice-casting.md)
- [US-English Starter Voice Set And Auto-Cast Preference](../specifications/us-english-starter-voice-set-and-auto-cast-preference.md)
- [Document-Specific Cast Voice Assignment Memory](../specifications/document-specific-cast-voice-assignment-memory.md)
- [Cast Voice Override Workflow](../specifications/cast-voice-override-workflow.md)

### [character gender identity extraction](specification-ancestors/character-gender-identity-extraction.md)

- [Character Identity Extraction Pass Ordering](../specifications/character-identity-extraction-pass-ordering.md)
- [Character Identity Output Schema](../specifications/character-identity-output-schema.md)
- [Explicit Character Identity Evidence](../specifications/explicit-character-identity-evidence.md)
- [Character Identity Descriptor Attachment](../specifications/character-identity-descriptor-attachment.md)
- [Character Pronoun Profile Extraction](../specifications/character-pronoun-profile-extraction.md)
- [Character Identity Conflict Resolution](../specifications/character-identity-conflict-resolution.md)

### [dialogue span and speaker attribution](specification-ancestors/dialogue-span-and-speaker-attribution.md)

- [Dialogue Span Detection](../specifications/dialogue-span-detection.md)
- [Quoted Dialogue Speaker Context Scanning](specification-ancestors/quoted-dialogue-speaker-context-scanning.md)
- [Speaker Attribution Contract](specification-ancestors/speaker-attribution-contract.md)

### [follow along reading surface ui](specification-ancestors/follow-along-reading-surface-ui.md)

- [Spoken Highlight Visual Presentation](../specifications/spoken-highlight-visual-presentation.md)
- [Reading Surface Contrast And Highlight Legibility](../specifications/reading-surface-contrast-and-highlight-legibility.md)
- [Follow-Along User Scroll Interaction](../specifications/follow-along-user-scroll-interaction.md)

### [live input and file menu ui](specification-ancestors/live-input-and-file-menu-ui.md)

- [Live Input Menu Placement and Playing-State Continuation](../specifications/live-input-menu-placement-and-playing-state-continuation.md)

### [multi voice playback routing](specification-ancestors/multi-voice-playback-routing.md)

- [Document-Load Voice Attribution Materialization](../specifications/document-load-voice-attribution-materialization.md)
- [Cast-Aware Speech Range Routing](../specifications/cast-aware-speech-range-routing.md)
- [Quoted Dialogue Voice Segmentation](../specifications/quoted-dialogue-voice-segmentation.md)
- [Voice-Routed Progress and Diagnostics](../specifications/voice-routed-progress-and-diagnostics.md)
- [Running-App Multi-Voice Playback Switching](../specifications/running-app-multi-voice-playback-switching.md)

### [primary reader surface ui](specification-ancestors/primary-reader-surface-ui.md)

- [Segmented Transport Capsule](../specifications/segmented-transport-capsule.md)
- [Primary Reader Control Set](../specifications/primary-reader-control-set.md)
- [Document Identity Outside Reading Surface](../specifications/document-identity-outside-reading-surface.md)
- [Integrated Secondary Voice Access](../specifications/integrated-secondary-voice-access.md)
- [Document-Load Cast Processing Overlay](../specifications/document-load-cast-processing-overlay.md)
- [Multi-Voice Mode Toggle And Cast Entrypoint](../specifications/multi-voice-mode-toggle-and-cast-entrypoint.md)
- [Feedback Surface Contrast Readability](../specifications/feedback-surface-contrast-readability.md)
- [Transient Feedback Toast Behavior](../specifications/transient-feedback-toast-behavior.md)
- [Compact Voice Domain Control And Word Count De-Emphasis](../specifications/compact-voice-domain-control-and-word-count-de-emphasis.md)

### [quoted dialogue speaker context scanning](specification-ancestors/quoted-dialogue-speaker-context-scanning.md)

- [Explicit Speaker Tag Attribution](../specifications/explicit-speaker-tag-attribution.md)
- [Adjacent Speaker Context Attribution](../specifications/adjacent-speaker-context-attribution.md)
- [Paragraph Ownership And Dialogue Alternation](../specifications/paragraph-ownership-and-dialogue-alternation.md)
- [Speaker Pronoun Resolution And Persistence](../specifications/speaker-pronoun-resolution-and-persistence.md)

### [reader options and secondary settings ui](specification-ancestors/reader-options-and-secondary-settings-ui.md)

- [Reader Preferences Controls](../specifications/reader-preferences-controls.md)
- [Sleep Timer And Timing Surface](../specifications/sleep-timer-and-timing-surface.md)
- [Reader Diagnostics And Source Panels](../specifications/reader-diagnostics-and-source-panels.md)

### [reader session continuity and live input](specification-ancestors/reader-session-continuity-and-live-input.md)

- [File-Backed Document Restore And Directory Continuity](../specifications/file-backed-document-restore-and-directory-continuity.md)
- [Remembered Reading Position And Startup Resume](../specifications/remembered-reading-position-and-startup-resume.md)
- [Watched-File Session Refresh](../specifications/watched-file-session-refresh.md)

### [speaker attribution contract](specification-ancestors/speaker-attribution-contract.md)

- [Speaker Attribution Outcome Schema](../specifications/speaker-attribution-outcome-schema.md)
- [Speaker Attribution Priority And Unknown Handling](../specifications/speaker-attribution-priority-and-unknown-handling.md)

### [spoken text highlighting and reading focus](specification-ancestors/spoken-text-highlighting-and-reading-focus.md)

- [Spoken Text Selection and Display Mapping](../specifications/spoken-text-selection-and-display-mapping.md)
- [Reading Focus Follow Policy](../specifications/reading-focus-follow-policy.md)
- [Follower Progress Coalescing And Drift Resynchronization](../specifications/follower-progress-coalescing-and-drift-resynchronization.md)

### [theme and appearance modes ui](specification-ancestors/theme-and-appearance-modes-ui.md)

- [Appearance Mode Selection and System Following](../specifications/appearance-mode-selection-and-system-following.md)

### [visual design system adoption ui](specification-ancestors/visual-design-system-adoption-ui.md)

- [App-Wide Semantic Theme Token Adoption](../specifications/app-wide-semantic-theme-token-adoption.md)
- [Editorial Typography Role Application](../specifications/editorial-typography-role-application.md)
- [Secondary Surface Component Family Consistency](../specifications/secondary-surface-component-family-consistency.md)
- [Reader Options Sectioned Information Hierarchy](../specifications/reader-options-sectioned-information-hierarchy.md)

### [voice library and cast management ui](specification-ancestors/voice-library-and-cast-management-ui.md)

- [Voice Preview Button Behavior](../specifications/voice-preview-button-behavior.md)
- [Voice Library Row and Information Affordance](../specifications/voice-library-row-and-information-affordance.md)
- [Cast Management Dialog Structure](../specifications/cast-management-dialog-structure.md)
- [Voice Management Dialog Contrast And Readability](../specifications/voice-management-dialog-contrast-and-readability.md)

### [voice library metadata and information surfacing](specification-ancestors/voice-library-metadata-and-information-surfacing.md)

- [Voice Metadata Model and Source Normalization](../specifications/voice-metadata-model-and-source-normalization.md)
- [US-English Starter Voice Set And Auto-Cast Preference](../specifications/us-english-starter-voice-set-and-auto-cast-preference.md)

## Old planning

- [Specification completion checklist](../planning/archive/progression.md)
- [Imported-document rework plan](../planning/archive/imported-document-rework-plan.md)
- [Earlier runtime alignment note](../planning/archive/document-preparation-runtime-alignment.md)

The [active plan](../planning/prepared-document-runtime.plan) supersedes these as an execution entry point. Thirteen less-refined ancestors remain listed in the [legacy index](../specifications/README.md) rather than being archived without a semantic decision.
