# Project Documentation

This directory is the authoritative source of project understanding for `Read Aloud`.

The documentation is organized around a product definition plus six supporting domains:

- `agents/`: project-specific agent operating rules
- `ui/`: interface structure, interaction semantics, complexity layering, and durable visual behavior
- `product-definition.md`: feature definition, user expectations, scope, and non-goals
- `architecture/`: structural truth, boundaries, responsibilities, and data flow
- `specifications/`: behavioral contracts, rules, thresholds, and acceptance criteria
- `planning/`: active work sequencing, dependencies, and implementation plans
- `research/`: accumulated findings, observations, and external dependency notes

## Current Document Map

### Agents

- [Project Agent Rules](agents/README.md)

### UI Definitions

- [UI Definitions Index](ui/README.md)
- [UI System Overview](ui/ui-system-overview.md)
- [Primary Surface and Complexity Layering](ui/primary-surface-and-complexity-layering.md)
- [Control State Semantics](ui/control-state-semantics.md)
- [Theme and Appearance Modes](ui/theme-and-appearance-modes.md)
- [Live Input and File Menu Behavior](ui/live-input-and-file-menu-behavior.md)

### Product

- [Product Definition](product-definition.md)

### Architecture

- [Architecture Index](architecture/README.md)
- [System Overview](architecture/system-overview.md)
- [Document and Speech Pipeline](architecture/document-speech-pipeline.md)
- [Normalized Content and Position Mapping](architecture/normalized-content-and-position-mapping.md)
- [Speech Enrichment and Narration](architecture/speech-enrichment-and-narration.md)
- [Pronunciation Planning and TTS Artifacts](architecture/pronunciation-planning-and-tts-artifacts.md)
- [English Pronunciation Profiles and Rule Modularity](architecture/english-pronunciation-profiles-and-rule-modularity.md)
- [Engine Pronunciation Expression and Capability Adaptation](architecture/engine-pronunciation-expression-and-capability-adaptation.md)
- [Speech Runtime Messaging Boundary](architecture/speech-runtime-messaging-boundary.md)
- [Playback Orchestration and Synthesis Boundaries](architecture/playback-orchestration-and-synthesis-boundaries.md)
- [Audio Export and Headless Execution](architecture/audio-export-and-headless-execution.md)

### Specifications

- [Specifications Index](specifications/README.md)
- [Normalized Document Model](specifications/normalized-document-model.md)
- [PositionMap](specifications/position-map.md)
- [Pronunciation Planning and TTS Artifacts](specifications/pronunciation-planning-and-tts-artifacts.md)
- [English Pronunciation Profiles and Rule Modularity](specifications/english-pronunciation-profiles-and-rule-modularity.md)
- [Engine Pronunciation Expression and Capability Adaptation](specifications/engine-pronunciation-expression-and-capability-adaptation.md)
- [Speech Annotation Set](specifications/speech-annotation-set.md)
- [Speech Runtime Messaging Boundary](specifications/speech-runtime-messaging-boundary.md)
- [English Pronunciation Profile Model](specifications/english-pronunciation-profile-model.md)
- [English Pronunciation Profile Selection Policy](specifications/english-pronunciation-profile-selection-policy.md)
- [Pronunciation Resource Layering Policy](specifications/pronunciation-resource-layering-policy.md)
- [Pronunciation Rule Module Contract](specifications/pronunciation-rule-module-contract.md)
- [English Suffix Allomorph Module](specifications/english-suffix-allomorph-module.md)
- [Document-Time Profile-Aware Pronunciation Planning](specifications/document-time-profile-aware-pronunciation-planning.md)
- [Voice-Session Profile-Aware Pronunciation Realization](specifications/voice-session-profile-aware-pronunciation-realization.md)
- [Engine Capability Model](specifications/engine-capability-model.md)
- [Engine Adapter Translation Boundary](specifications/engine-adapter-translation-boundary.md)
- [Voice and Session Realization](specifications/voice-session-realization.md)
- [Narration State](specifications/narration-state.md)
- [Imported Document Playback](specifications/imported-document-playback.md)
- [Synthesis Boundary Policy](specifications/synthesis-boundary-policy.md)
- [Playback Quality Instrumentation](specifications/playback-quality-instrumentation.md)
- [Audio Export and Headless Execution](specifications/audio-export-and-headless-execution.md)

### Planning

- [Planning Index](planning/README.md)
- [Progression](planning/progression.md)
- [Imported Document Rework Plan](planning/imported-document-rework-plan.md)
- [Open Source Compliance Plan](planning/open-source-compliance-plan.md)

### Research

- [Research Index](research/README.md)
- [Document-Time vs Voice-Time Speech Processing](research/architecture-questions/document-time-vs-voice-time-speech-processing-2026-03-30.md)
- [Flutter Concurrency, Message Boundaries, and Runtime Decoupling](research/architecture-questions/flutter-concurrency-message-boundaries-and-runtime-decoupling-2026-03-30.md)
- [Narration State and Voice-Specific Realization](research/architecture-questions/narration-state-and-voice-specific-realization-2026-03-30.md)
- [PositionMap Granularity and Anchor Model](research/document-processing/position-map-granularity-and-anchor-model-2026-03-30.md)
- [Chunk Boundary and Silence Policy](research/speech-quality/chunk-boundary-and-silence-policy-2026-03-30.md)
- [English Pronunciation Dictionary Backstop and Special Cases](research/speech-quality/english-pronunciation-dictionary-backstop-and-special-cases-2026-04-02.md)
- [English Possessive Pronunciation in TTS](research/speech-quality/english-possessive-pronunciation-in-tts-2026-03-31.md)
- [High-Quality TTS and Narration Gap](research/speech-quality/high-quality-tts-and-narration-gap-2026-03-30.md)
- [Kokoro Flutter Pronunciation and Override Behavior](research/speech-quality/kokoro-flutter-pronunciation-and-override-behavior-2026-03-30.md)
- [Kokoro Control Surface and Limits](research/speech-quality/kokoro-control-surface-and-limits-2026-03-30.md)
- [Long-Form TTS Evaluation and Instrumentation](research/speech-quality/long-form-tts-evaluation-and-instrumentation-2026-03-30.md)
- [Plain Text to Natural TTS Prior Art](research/plain-text-to-natural-tts-prior-art-2026-03-29.md)
- [Product Needs Ecosystem Survey](research/product-needs-ecosystem-survey-2026-03-29.md)
- [Imported Document Observations](research/imported-document-observations-2026-03-29.md)
- [Open Source Licensing Notes](research/open-source-licensing-notes.md)

## Legacy Root Documents

The following root-level files now serve only as pointers into `project/`:

- [PROJECT_PLAN.md](../PROJECT_PLAN.md)
- [OPEN_SOURCE_LICENSING_PLAN.md](../OPEN_SOURCE_LICENSING_PLAN.md)
