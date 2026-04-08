# Progression

Last updated: April 7, 2026
Status: Active progression

## Purpose

This document is the execution sequence for implementation of the current final leaf specifications.

It includes only leaf specifications that are marked final.

Checked support leaves do not, by themselves, mean a user-facing feature is surfaced in the running app.

For user-facing branches, the unchecked surfaced leaves remain the feature-completion gates.

Implementation checkboxes track feature-spec implementation work.

Test specification checkboxes track verification work against the paired documents in `project/test-specifications/`.

## Ordering Rule

- primary ordering is dependency order
- when multiple specifications are unblocked, secondary ordering is alphabetical

## Core Functionality

### Normalized Content Primitives

- [x] [Normalized Import Result Envelope](../specifications/normalized-import-result-envelope.md)
- [x] [Normalized Layer Shared Identity and Metadata](../specifications/normalized-layer-shared-identity-and-metadata.md)
- [x] [Normalized Layer Compatibility and Migration](../specifications/normalized-layer-compatibility-and-migration.md)
- [x] [Display Document](../specifications/display-document.md)
- [x] [Speech Document](../specifications/speech-document.md)
- [x] [PositionMap](../specifications/position-map.md)

### Import Normalization Behavior

- [x] [Import Source Acquisition and Fingerprinting](../specifications/import-source-acquisition-and-fingerprinting.md)
- [x] [Import Diagnostics Taxonomy](../specifications/import-diagnostics-taxonomy.md)
- [x] [Import Structural Cleanup and Visible Content Preservation](../specifications/import-structural-cleanup-and-visible-content-preservation.md)
- [x] [Markup and Archive Common Structural Normalization](../specifications/markup-and-archive-common-structural-normalization.md)
- [x] [HTML Document Normalization](../specifications/html-document-normalization.md)
- [x] [EPUB Document Normalization](../specifications/epub-document-normalization.md)
- [x] [DOCX Document Normalization](../specifications/docx-document-normalization.md)
- [x] [Lossy Text Common Heuristic Grouping](../specifications/lossy-text-common-heuristic-grouping.md)
- [x] [Plain and Shared Text Normalization](../specifications/plain-and-shared-text-normalization.md)
- [x] [PDF Extracted Text Normalization](../specifications/pdf-extracted-text-normalization.md)
- [x] [RTF Flattened Text Normalization](../specifications/rtf-flattened-text-normalization.md)
- [x] [Import Failure and Partial Success Semantics](../specifications/import-failure-and-partial-success-semantics.md)
- [x] [Line Wrap and Paragraph Recovery](../specifications/line-wrap-and-paragraph-recovery.md)

### Speech Enrichment Foundations

- [x] [Speech Annotation Envelope Model](../specifications/speech-annotation-envelope-model.md)
- [x] [Narration State](../specifications/narration-state.md)
- [x] [Pause and Break Taxonomy](../specifications/pause-and-break-taxonomy.md)
- [x] [Emphasis Candidate Model](../specifications/emphasis-candidate-model.md)
- [x] [Discourse Role Annotation Model](../specifications/discourse-role-annotation-model.md)
- [x] [Pronunciation Candidate Model](../specifications/pronunciation-candidate-model.md)
- [x] [Say-As Candidate Model](../specifications/say-as-candidate-model.md)

### Modular English Pronunciation Profiles

- [x] [English Pronunciation Profile Model](../specifications/english-pronunciation-profile-model.md)
- [x] [English Pronunciation Profile Selection Policy](../specifications/english-pronunciation-profile-selection-policy.md)
- [x] [Pronunciation Resource Layering Policy](../specifications/pronunciation-resource-layering-policy.md)
- [x] [Pronunciation Rule Module Contract](../specifications/pronunciation-rule-module-contract.md)
- [x] [English Suffix Allomorph Module](../specifications/english-suffix-allomorph-module.md)
- [x] [Document-Time Profile-Aware Pronunciation Planning](../specifications/document-time-profile-aware-pronunciation-planning.md)
- [x] [Voice-Session Profile-Aware Pronunciation Realization](../specifications/voice-session-profile-aware-pronunciation-realization.md)

### Engine Pronunciation Expression and Capability Adaptation

- [x] [Engine Capability Model](../specifications/engine-capability-model.md)
- [x] [Engine Adapter Translation Boundary](../specifications/engine-adapter-translation-boundary.md)
- [x] [Kokoro Phoneme Inventory Adaptation](../specifications/kokoro-phoneme-inventory-adaptation.md)

### Pronunciation Planning and TTS Artifacts

- [x] [Pronunciation Artifact Model](../specifications/pronunciation-artifact-model.md)
- [x] [Document-Time Pronunciation Planner](../specifications/document-time-pronunciation-planner.md)
- [x] [Voice-Session Pronunciation Realization](../specifications/voice-session-pronunciation-realization.md)
- [x] [Engine Pronunciation Translation Policy](../specifications/engine-pronunciation-translation-policy.md)
- [x] [Pronunciation Fallback and Traceability](../specifications/pronunciation-fallback-and-traceability.md)
- [x] [TTS Runtime Chunk Request Derivation](../specifications/tts-runtime-chunk-request-derivation.md)

### Voice and Session Realization

- [x] [Voice Session Realization Envelope](../specifications/voice-session-realization-envelope.md)
- [x] [Boundary Intent Realization](../specifications/boundary-intent-realization.md)
- [x] [Emphasis Intent Realization](../specifications/emphasis-intent-realization.md)
- [x] [Engine Intent Translation Policy](../specifications/engine-intent-translation-policy.md)
- [x] [Pronunciation Realization Precedence](../specifications/pronunciation-realization-precedence.md)
- [x] [Realization Window Policy](../specifications/realization-window-policy.md)

### Narrative Casting and Multi-Voice Playback

- [x] [Dialogue Span Detection](../specifications/dialogue-span-detection.md)
- [x] [Speaker Attribution Outcome Schema](../specifications/speaker-attribution-outcome-schema.md)
- [x] [Speaker Attribution Priority And Unknown Handling](../specifications/speaker-attribution-priority-and-unknown-handling.md)
- [x] [Explicit Speaker Tag Attribution](../specifications/explicit-speaker-tag-attribution.md)
- [x] [Adjacent Speaker Context Attribution](../specifications/adjacent-speaker-context-attribution.md)
- [x] [Paragraph Ownership And Dialogue Alternation](../specifications/paragraph-ownership-and-dialogue-alternation.md)
- [x] [Speaker Pronoun Resolution And Persistence](../specifications/speaker-pronoun-resolution-and-persistence.md)
- [x] [Character Cast Registry Model](../specifications/character-cast-registry-model.md)
- [x] [Character Reference Consolidation And Alias Clustering](../specifications/character-reference-consolidation-and-alias-clustering.md)
- [x] [Character Identity Extraction Pass Ordering](../specifications/character-identity-extraction-pass-ordering.md)
- [x] [Character Identity Output Schema](../specifications/character-identity-output-schema.md)
- [x] [Explicit Character Identity Evidence](../specifications/explicit-character-identity-evidence.md)
- [x] [Character Identity Descriptor Attachment](../specifications/character-identity-descriptor-attachment.md)
- [x] [Character Pronoun Profile Extraction](../specifications/character-pronoun-profile-extraction.md)
- [x] [Character Identity Conflict Resolution](../specifications/character-identity-conflict-resolution.md)
- [x] [Voice Metadata Model and Source Normalization](../specifications/voice-metadata-model-and-source-normalization.md)
- [x] [Automatic Voice Casting and Override Resolution](../specifications/automatic-voice-casting-and-override-resolution.md)
- [x] [Context-Aware Automatic Voice Casting](../specifications/context-aware-automatic-voice-casting.md)
- [x] [US-English Starter Voice Set And Auto-Cast Preference](../specifications/us-english-starter-voice-set-and-auto-cast-preference.md)
- [x] [Document-Specific Cast Voice Assignment Memory](../specifications/document-specific-cast-voice-assignment-memory.md)
- [x] [Document-Load Voice Attribution Materialization](../specifications/document-load-voice-attribution-materialization.md)
- [x] [Cast-Aware Speech Range Routing](../specifications/cast-aware-speech-range-routing.md)
- [x] [Quoted Dialogue Voice Segmentation](../specifications/quoted-dialogue-voice-segmentation.md)
- [x] [Voice-Routed Progress and Diagnostics](../specifications/voice-routed-progress-and-diagnostics.md)
- [x] [Cast Voice Override Workflow](../specifications/cast-voice-override-workflow.md)
- [x] [Running-App Multi-Voice Playback Switching](../specifications/running-app-multi-voice-playback-switching.md)

#### Test Specifications

- [x] [Test Specification: Cast Voice Override Workflow](../test-specifications/cast-voice-override-workflow.md)
- [x] [Test Specification: US-English Starter Voice Set And Auto-Cast Preference](../test-specifications/us-english-starter-voice-set-and-auto-cast-preference.md)
- [x] [Test Specification: Document-Specific Cast Voice Assignment Memory](../test-specifications/document-specific-cast-voice-assignment-memory.md)
- [x] [Test Specification: Quoted Dialogue Voice Segmentation](../test-specifications/quoted-dialogue-voice-segmentation.md)
- [x] [Test Specification: Running-App Multi-Voice Playback Switching](../test-specifications/running-app-multi-voice-playback-switching.md)

### Speech Runtime Boundary

- [x] [Platform Capability and Fallback Policy](../specifications/platform-capability-and-fallback-policy.md)
- [x] [Sendable Runtime DTO Contract](../specifications/sendable-runtime-dto-contract.md)
- [x] [Native Engine Queue Policy](../specifications/native-engine-queue-policy.md)
- [x] [Speech Runtime Lifecycle and Ownership](../specifications/speech-runtime-lifecycle-and-ownership.md)
- [x] [Speech Runtime Command Protocol](../specifications/speech-runtime-command-protocol.md)
- [x] [Speech Runtime Event Protocol](../specifications/speech-runtime-event-protocol.md)

### Generation Pipeline

- [x] [First-Chunk Startup Contract](../specifications/first-chunk-startup-contract.md)
- [x] [Imported Playback Responsiveness Policy](../specifications/imported-playback-responsiveness-policy.md)
- [x] [Chunk Planning](../specifications/chunk-planning.md)
- [x] [Generated Audio Cache](../specifications/generated-audio-cache.md)
- [x] [Speech Worker Pipeline](../specifications/speech-worker-pipeline.md)

### Boundary and Playback Execution

- [x] [Boundary Candidate Metadata Contract](../specifications/boundary-candidate-metadata-contract.md)
- [x] [Boundary Silence Thresholds](../specifications/boundary-silence-thresholds.md)
- [x] [Trim-and-Cap Join Correction](../specifications/trim-and-cap-join-correction.md)
- [x] [Initial and Resumed Boundary Handling](../specifications/initial-and-resumed-boundary-handling.md)
- [x] [Boundary-Corrected Chunk Output and Reuse](../specifications/boundary-corrected-chunk-output-and-reuse.md)
- [x] [Playback Coordination](../specifications/playback-coordination.md)
- [x] [Playback Progress and Jump Mapping](../specifications/playback-progress-and-jump-mapping.md)
- [x] [Document Replacement Playback Reset And Stale Event Rejection](../specifications/document-replacement-playback-reset-and-stale-event-rejection.md)
- [x] [Spoken Text Selection and Display Mapping](../specifications/spoken-text-selection-and-display-mapping.md)
- [x] [Reading Focus Follow Policy](../specifications/reading-focus-follow-policy.md)

#### Test Specifications

- [x] [Test Specification: Playback Coordination](../test-specifications/playback-coordination.md)
- [x] [Test Specification: Playback Progress And Jump Mapping](../test-specifications/playback-progress-and-jump-mapping.md)
- [x] [Test Specification: Document Replacement Playback Reset And Stale Event Rejection](../test-specifications/document-replacement-playback-reset-and-stale-event-rejection.md)

### App Shell And Platform Navigation UI

- [x] [Desktop Native Menu And Mobile Overflow Navigation](../specifications/desktop-native-menu-and-mobile-overflow-navigation.md)
- [x] [Mobile Overflow Menu Domain Grouping](../specifications/mobile-overflow-menu-domain-grouping.md)
- [x] [Desktop Reader Title Chrome Minimization](../specifications/desktop-reader-title-chrome-minimization.md)
- [x] [Reader-Only App Shell Until Authoring Exists](../specifications/studio-workspace-entry-and-reader-isolation.md)

#### Test Specifications

- [x] [Test Specification: Desktop Native Menu And Mobile Overflow Navigation](../test-specifications/desktop-native-menu-and-mobile-overflow-navigation.md)
- [x] [Test Specification: Mobile Overflow Menu Domain Grouping](../test-specifications/mobile-overflow-menu-domain-grouping.md)
- [x] [Test Specification: Desktop Reader Title Chrome Minimization](../test-specifications/desktop-reader-title-chrome-minimization.md)
- [x] [Test Specification: Reader-Only App Shell Until Authoring Exists](../test-specifications/studio-workspace-entry-and-reader-isolation.md)

### Visual Design System Adoption UI

- [x] [App-Wide Semantic Theme Token Adoption](../specifications/app-wide-semantic-theme-token-adoption.md)
- [x] [Editorial Typography Role Application](../specifications/editorial-typography-role-application.md)
- [x] [Secondary Surface Component Family Consistency](../specifications/secondary-surface-component-family-consistency.md)
- [x] [Reader Options Sectioned Information Hierarchy](../specifications/reader-options-sectioned-information-hierarchy.md)

#### Test Specifications

- [x] [Test Specification: App-Wide Semantic Theme Token Adoption](../test-specifications/app-wide-semantic-theme-token-adoption.md)
- [x] [Test Specification: Editorial Typography Role Application](../test-specifications/editorial-typography-role-application.md)
- [x] [Test Specification: Secondary Surface Component Family Consistency](../test-specifications/secondary-surface-component-family-consistency.md)
- [x] [Test Specification: Reader Options Sectioned Information Hierarchy](../test-specifications/reader-options-sectioned-information-hierarchy.md)

### Reader Surface and Voice Management UI

- [x] [Segmented Transport Capsule](../specifications/segmented-transport-capsule.md)
- [x] [Primary Reader Control Set](../specifications/primary-reader-control-set.md)
- [x] [Document Identity Outside Reading Surface](../specifications/document-identity-outside-reading-surface.md)
- [x] [Integrated Secondary Voice Access](../specifications/integrated-secondary-voice-access.md)
- [x] [Document-Load Cast Processing Overlay](../specifications/document-load-cast-processing-overlay.md)
- [x] [Multi-Voice Mode Toggle And Cast Entrypoint](../specifications/multi-voice-mode-toggle-and-cast-entrypoint.md)
- [x] [Feedback Surface Contrast Readability](../specifications/feedback-surface-contrast-readability.md)
- [x] [Transient Feedback Toast Behavior](../specifications/transient-feedback-toast-behavior.md)
- [x] [Compact Voice Domain Control And Word Count De-Emphasis](../specifications/compact-voice-domain-control-and-word-count-de-emphasis.md)
- [x] [Reader Preferences Controls](../specifications/reader-preferences-controls.md)
- [x] [Sleep Timer And Timing Surface](../specifications/sleep-timer-and-timing-surface.md)
- [x] [Reader Diagnostics And Source Panels](../specifications/reader-diagnostics-and-source-panels.md)
- [x] [Voice Preview Button Behavior](../specifications/voice-preview-button-behavior.md)
- [x] [Voice Library Row and Information Affordance](../specifications/voice-library-row-and-information-affordance.md)
- [x] [Voice Library Direct Character Assignment](../specifications/voice-library-direct-character-assignment.md)
- [x] [Cast Management Dialog Structure](../specifications/cast-management-dialog-structure.md)
- [x] [Voice Management Dialog Contrast And Readability](../specifications/voice-management-dialog-contrast-and-readability.md)
- [x] [Internal Document Serialization Format](../specifications/internal-document-serialization-format.md)
- [x] [Appearance Mode Selection And System Following](../specifications/appearance-mode-selection-and-system-following.md)
- [x] [Spoken Highlight Visual Presentation](../specifications/spoken-highlight-visual-presentation.md)
- [x] [Reading Surface Contrast And Highlight Legibility](../specifications/reading-surface-contrast-and-highlight-legibility.md)
- [x] [Follow-Along User Scroll Interaction](../specifications/follow-along-user-scroll-interaction.md)

#### Test Specifications

- [x] [Test Specification: Segmented Transport Capsule](../test-specifications/segmented-transport-capsule.md)
- [x] [Test Specification: Primary Reader Control Set](../test-specifications/primary-reader-control-set.md)
- [x] [Test Specification: Document Identity Outside Reading Surface](../test-specifications/document-identity-outside-reading-surface.md)
- [x] [Test Specification: Integrated Secondary Voice Access](../test-specifications/integrated-secondary-voice-access.md)
- [x] [Test Specification: Document-Load Cast Processing Overlay](../test-specifications/document-load-cast-processing-overlay.md)
- [x] [Test Specification: Multi-Voice Mode Toggle And Cast Entrypoint](../test-specifications/multi-voice-mode-toggle-and-cast-entrypoint.md)
- [x] [Test Specification: Feedback Surface Contrast Readability](../test-specifications/feedback-surface-contrast-readability.md)
- [x] [Test Specification: Transient Feedback Toast Behavior](../test-specifications/transient-feedback-toast-behavior.md)
- [x] [Test Specification: Compact Voice Domain Control And Word Count De-Emphasis](../test-specifications/compact-voice-domain-control-and-word-count-de-emphasis.md)
- [x] [Test Specification: Reader Preferences Controls](../test-specifications/reader-preferences-controls.md)
- [x] [Test Specification: Sleep Timer And Timing Surface](../test-specifications/sleep-timer-and-timing-surface.md)
- [x] [Test Specification: Reader Diagnostics And Source Panels](../test-specifications/reader-diagnostics-and-source-panels.md)
- [x] [Test Specification: Voice Preview Button Behavior](../test-specifications/voice-preview-button-behavior.md)
- [x] [Test Specification: Voice Library Row And Information Affordance](../test-specifications/voice-library-row-and-information-affordance.md)
- [x] [Test Specification: Voice Library Direct Character Assignment](../test-specifications/voice-library-direct-character-assignment.md)
- [x] [Test Specification: Cast Management Dialog Structure](../test-specifications/cast-management-dialog-structure.md)
- [x] [Test Specification: Voice Management Dialog Contrast And Readability](../test-specifications/voice-management-dialog-contrast-and-readability.md)
- [x] [Test Specification: Appearance Mode Selection And System Following](../test-specifications/appearance-mode-selection-and-system-following.md)
- [x] [Test Specification: Spoken Highlight Visual Presentation](../test-specifications/spoken-highlight-visual-presentation.md)
- [x] [Test Specification: Reading Surface Contrast And Highlight Legibility](../test-specifications/reading-surface-contrast-and-highlight-legibility.md)
- [x] [Test Specification: Follow-Along User Scroll Interaction](../test-specifications/follow-along-user-scroll-interaction.md)

### Reader Session and Live Input

- [x] [File-Backed Document Restore And Directory Continuity](../specifications/file-backed-document-restore-and-directory-continuity.md)
- [x] [Persistent Folder Access For Startup Restore](../specifications/persistent-file-access-for-startup-restore.md)
- [x] [Remembered Reading Position And Startup Resume](../specifications/remembered-reading-position-and-startup-resume.md)
- [x] [Watched-File Session Refresh](../specifications/watched-file-session-refresh.md)
- [x] [Live Input Menu Placement And Playing-State Continuation](../specifications/live-input-menu-placement-and-playing-state-continuation.md)

#### Test Specifications

- [x] [Test Specification: File-Backed Document Restore And Directory Continuity](../test-specifications/file-backed-document-restore-and-directory-continuity.md)
- [x] [Test Specification: Persistent Folder Access For Startup Restore](../test-specifications/persistent-file-access-for-startup-restore.md)
- [x] [Test Specification: Remembered Reading Position And Startup Resume](../test-specifications/remembered-reading-position-and-startup-resume.md)
- [x] [Test Specification: Watched-File Session Refresh](../test-specifications/watched-file-session-refresh.md)
- [x] [Test Specification: Live Input Menu Placement And Playing-State Continuation](../test-specifications/live-input-menu-placement-and-playing-state-continuation.md)

## Obligate Specifications

- [x] [Playback Quality Instrumentation](../specifications/playback-quality-instrumentation.md)
- [x] [Pronunciation Diagnostics and Observability](../specifications/pronunciation-diagnostics-and-observability.md)
- [x] [Repository Readme and GitHub Community Files](../specifications/repository-readme-and-github-community-files.md)
- [x] [Audio Export Assembly](../specifications/audio-export-assembly.md)
- [x] [Command-Line Mode Selection](../specifications/command-line-mode-selection.md)
- [x] [Headless Synthesis Session](../specifications/headless-synthesis-session.md)
- [x] [In-App Audio Export Workflow](../specifications/in-app-audio-export-workflow.md)
- [x] [Speech QA Debug Tooling](../specifications/speech-qa-debug-tooling.md)

## Notes

- This document contains only final leaf specifications and paired feature test specifications.
- If new child specifications are created later, this document should be updated before implementation continues.
