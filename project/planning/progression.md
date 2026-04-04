# Progression

Last updated: April 3, 2026
Status: Active progression

## Purpose

This document is the execution sequence for implementation of the current final leaf specifications.

It includes only leaf specifications that are marked final.

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

### Reader Session and Live Input

- [x] [Reader Session Continuity and Live Input](../specifications/reader-session-continuity-and-live-input.md)

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

- This document contains only final leaf specifications.
- If new child specifications are created later, this document should be updated before implementation continues.
