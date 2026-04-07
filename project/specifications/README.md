# Specifications Index

Specifications define exactly how specific parts of `Read Aloud` must behave and be implemented.

They are intentionally narrower than architecture documents. For any architectural area, there may be several focused specifications covering concrete data contracts, algorithms, thresholds, and state behavior.

## Current Documents

### Normalized Document Layer

- [Normalized Document Model](normalized-document-model.md)
  Umbrella specification for normalized importer output and cross-document invariants.
- [Normalized Import Result Envelope](normalized-import-result-envelope.md)
  Defines the shared normalized importer output envelope consumed by downstream layers.
- [Normalized Layer Shared Identity and Metadata](normalized-layer-shared-identity-and-metadata.md)
  Defines shared identity, metadata, versioning, and diagnostics invariants across the normalized layer.
- [Normalized Layer Compatibility and Migration](normalized-layer-compatibility-and-migration.md)
  Defines coexistence rules for legacy compatibility views during normalized-layer migration.
- [Display Document](display-document.md)
  Defines the rendering-side document structure and block model.
- [Speech Document](speech-document.md)
  Defines the speech-side document structure, segment rules, and mapping metadata.
- [PositionMap](position-map.md)
  Defines the hybrid display-to-speech mapping model, offsets, recovery anchors, and optional source-native anchors.
- [Importer Normalization Contract](importer-normalization-contract.md)
  Defines the importer pipeline, normalization phases, per-format rules, and diagnostics contract.
- [Import Source Acquisition and Fingerprinting](import-source-acquisition-and-fingerprinting.md)
  Defines importer entrypoint source acquisition and stable source-identity derivation.
- [Import Diagnostics Taxonomy](import-diagnostics-taxonomy.md)
  Defines stable importer diagnostic codes, severities, and emission rules.
- [Import Structural Cleanup and Visible Content Preservation](import-structural-cleanup-and-visible-content-preservation.md)
  Defines removal of parser noise while preserving meaningful visible structure and media placeholders.
- [Markup and Archive Document Normalization](markup-and-archive-document-normalization.md)
  Umbrella specification for structural normalization of HTML, EPUB, and DOCX families.
- [Markup and Archive Common Structural Normalization](markup-and-archive-common-structural-normalization.md)
  Defines common normalization behavior for markup- and archive-backed families.
- [HTML Document Normalization](html-document-normalization.md)
  Defines HTML-specific normalization behavior.
- [EPUB Document Normalization](epub-document-normalization.md)
  Defines EPUB-specific normalization behavior.
- [DOCX Document Normalization](docx-document-normalization.md)
  Defines DOCX-specific normalization behavior.
- [Lossy Extracted Text Normalization](lossy-extracted-text-normalization.md)
  Umbrella specification for normalization of plain/shared text, PDF extracted text, and flattened RTF.
- [Lossy Text Common Heuristic Grouping](lossy-text-common-heuristic-grouping.md)
  Defines common heuristic-grouping behavior for lossy extracted-text families.
- [Plain and Shared Text Normalization](plain-and-shared-text-normalization.md)
  Defines normalization behavior for plain text and pasted/shared text.
- [PDF Extracted Text Normalization](pdf-extracted-text-normalization.md)
  Defines normalization behavior for extracted PDF text.
- [RTF Flattened Text Normalization](rtf-flattened-text-normalization.md)
  Defines normalization behavior for flattened RTF text.
- [Import Failure and Partial Success Semantics](import-failure-and-partial-success-semantics.md)
  Defines fatal failure, degraded success, partial success, and unsupported-format importer outcomes.
- [Line Wrap and Paragraph Recovery](line-wrap-and-paragraph-recovery.md)
  Defines the lightweight paragraph-recovery heuristics used for plain and lossy extracted text.

### Speech Enrichment and Narration

- [Speech Annotation Set](speech-annotation-set.md)
  Defines the document-time reusable speech-annotation layer.
- [Speech Annotation Envelope Model](speech-annotation-envelope-model.md)
  Defines the shared container, ids, ranges, provenance, confidence, and cache rules for document-time speech annotations.
- [Pause and Break Taxonomy](pause-and-break-taxonomy.md)
  Defines the internal break-strength vocabulary used by document-time annotations.
- [Emphasis Candidate Model](emphasis-candidate-model.md)
  Defines how document-time emphasis candidates are represented before voice/session realization.
- [Discourse Role Annotation Model](discourse-role-annotation-model.md)
  Defines the document-time discourse-role vocabulary used to carry local delivery mode.
- [Dialogue Span and Speaker Attribution](dialogue-span-and-speaker-attribution.md)
  Umbrella specification for dialogue span detection and speaker attribution before playback.
- [Dialogue Span Detection](dialogue-span-detection.md)
  Defines how dialogue-like spans are identified and anchored to normalized speech ranges.
- [Quoted Dialogue Speaker Context Scanning](quoted-dialogue-speaker-context-scanning.md)
  Umbrella specification for the ordered local heuristics that scan quoted dialogue for likely speakers.
- [Speaker Attribution Contract](speaker-attribution-contract.md)
  Umbrella specification for attribution output structure, rule trace, and provider-independent result handling.
- [Speaker Attribution Outcome Schema](speaker-attribution-outcome-schema.md)
  Defines the per-quote attribution fields including speaker, confidence, rule_used, and evidence_span.
- [Speaker Attribution Priority And Unknown Handling](speaker-attribution-priority-and-unknown-handling.md)
  Defines the priority ladder, override behavior, and unknown-threshold semantics for speaker attribution.
- [Explicit Speaker Tag Attribution](explicit-speaker-tag-attribution.md)
  Defines authoritative same-sentence quote-tag attribution patterns.
- [Adjacent Speaker Context Attribution](adjacent-speaker-context-attribution.md)
  Defines before-and-after local context attribution when no same-sentence tag is available.
- [Paragraph Ownership And Dialogue Alternation](paragraph-ownership-and-dialogue-alternation.md)
  Defines paragraph-level ownership and local alternation heuristics for unattributed dialogue.
- [Speaker Pronoun Resolution And Persistence](speaker-pronoun-resolution-and-persistence.md)
  Defines lower-priority pronoun and most-recent-speaker fallback behavior.
- [Document-Load Voice Attribution Materialization](document-load-voice-attribution-materialization.md)
  Defines the document-owned narrator-versus-character attribution structure built during import and reused by playback, export, and headless synthesis.
- [Pronunciation Candidate Model](pronunciation-candidate-model.md)
  Defines reusable pronunciation candidates captured before voice-specific realization.
- [Say-As Candidate Model](say-as-candidate-model.md)
  Defines semantic `say-as` reading intent and its shared class vocabulary.
- [Pronunciation Planning and TTS Artifacts](pronunciation-planning-and-tts-artifacts.md)
  Umbrella specification for document-time pronunciation planning, voice/session pronunciation realization, and TTS artifact consumption.
- [English Pronunciation Profiles and Rule Modularity](english-pronunciation-profiles-and-rule-modularity.md)
  Umbrella specification for selectable English pronunciation profiles, layered resources, and productive rule modules.
- [Engine Pronunciation Expression and Capability Adaptation](engine-pronunciation-expression-and-capability-adaptation.md)
  Umbrella specification for explicit engine capability modeling and adapter-boundary translation of app-owned pronunciation artifacts.
- [Pronunciation Artifact Model](pronunciation-artifact-model.md)
  Defines the durable pronunciation sidecar model attached to normalized speech content.
- [Document-Time Pronunciation Planner](document-time-pronunciation-planner.md)
  Defines the document-time planner that emits cached pronunciation artifacts from normalized content.
- [Voice-Session Pronunciation Realization](voice-session-pronunciation-realization.md)
  Defines how cached pronunciation artifacts are resolved for the active voice, rate, and narration window.
- [TTS Artifact Consumption Contract](tts-artifact-consumption-contract.md)
  Umbrella specification for runtime consumption, engine translation, and fallback traceability of pronunciation-aware TTS artifacts.
- [TTS Runtime Chunk Request Derivation](tts-runtime-chunk-request-derivation.md)
  Defines how chunk planning output and `TtsArtifactSet` are paired into runtime-ready chunk requests.
- [Engine Pronunciation Translation Policy](engine-pronunciation-translation-policy.md)
  Defines direct, approximated, and deferred engine-adapter handling of realized pronunciation artifacts.
- [Pronunciation Fallback and Traceability](pronunciation-fallback-and-traceability.md)
  Defines how missing, unresolved, approximated, and deferred pronunciation cases remain visible through runtime and export flows.
- [Pronunciation Diagnostics and Observability](pronunciation-diagnostics-and-observability.md)
  Defines how pronunciation planning and realization expose unresolved, resolved, and approximated cases.
- [English Pronunciation Profile Model](english-pronunciation-profile-model.md)
  Defines the stable profile data model for English variant and accent-overlay pronunciation behavior.
- [English Pronunciation Profile Selection Policy](english-pronunciation-profile-selection-policy.md)
  Defines how the active English pronunciation profile is selected from voice, locale, engine, and future user preference.
- [Pronunciation Resource Layering Policy](pronunciation-resource-layering-policy.md)
  Defines deterministic resource merge order across global, variant, overlay, imported, and user pronunciation resources.
- [Pronunciation Rule Module Contract](pronunciation-rule-module-contract.md)
  Defines the reusable contract for productive pronunciation rule modules.
- [English Suffix Allomorph Module](english-suffix-allomorph-module.md)
  Defines the productive English `s`-class rule module used for possessive and related endings.
- [Document-Time Profile-Aware Pronunciation Planning](document-time-profile-aware-pronunciation-planning.md)
  Defines how document-time pronunciation planning becomes aware of the selected English pronunciation profile.
- [Voice-Session Profile-Aware Pronunciation Realization](voice-session-profile-aware-pronunciation-realization.md)
  Defines how active pronunciation realization becomes aware of the selected English pronunciation profile.
- [Engine Capability Model](engine-capability-model.md)
  Defines the app-owned capability profile used to decide what an engine can express directly, approximate, or only defer.
- [Engine Adapter Translation Boundary](engine-adapter-translation-boundary.md)
  Defines where runtime-ready chunk requests and pronunciation artifacts become engine-native payloads.
- [Kokoro Phoneme Inventory Adaptation](kokoro-phoneme-inventory-adaptation.md)
  Defines the narrow engine-boundary translation from canonical internal IPA to Kokoro/Misaki phoneme symbols for direct phoneme payloads.
- [Voice and Session Realization](voice-session-realization.md)
  Defines how cached speech intent becomes active voice-specific planner input.
- [Voice Session Realization Envelope](voice-session-realization-envelope.md)
  Defines the shared request/response envelope for active-session realization and its canonical `TtsArtifactSet` output.
- [Realization Window Policy](realization-window-policy.md)
  Defines how much content voice/session realization should cover at a time.
- [Boundary Intent Realization](boundary-intent-realization.md)
  Defines how pause and phrase annotations become active-session boundary intent.
- [Emphasis Intent Realization](emphasis-intent-realization.md)
  Defines how document-time emphasis candidates become active-session emphasis intent.
- [Pronunciation Realization Precedence](pronunciation-realization-precedence.md)
  Defines how pronunciation conflicts are resolved during realization.
- [Engine Intent Translation Policy](engine-intent-translation-policy.md)
  Defines how richer internal speech intent is translated to a specific engine such as Kokoro.
- [Narration State](narration-state.md)
  Defines the symbolic continuity state carried across chunks.
- [Character Cast Registry and Voice Assignment](character-cast-registry-and-voice-assignment.md)
  Umbrella specification for stable narrator/character cast identity, automatic voice assignment, and override precedence.
- [Character Cast Registry Model](character-cast-registry-model.md)
  Defines the stable narrator-plus-character registry used by casting and routing.
- [Character Reference Consolidation And Alias Clustering](character-reference-consolidation-and-alias-clustering.md)
  Defines conservative consolidation of near-duplicate character references into one cast entry.
- [Character Gender Identity Extraction](character-gender-identity-extraction.md)
  Umbrella specification for second-pass character identity extraction after canonical character creation.
- [Character Identity Extraction Pass Ordering](character-identity-extraction-pass-ordering.md)
  Defines when character identity extraction runs and what earlier passes it depends on.
- [Character Identity Output Schema](character-identity-output-schema.md)
  Defines the per-character identity fields, valid labels, and evidence separation rules.
- [Explicit Character Identity Evidence](explicit-character-identity-evidence.md)
  Defines extraction of explicit identity statements and appositions attached to canonical characters.
- [Character Identity Descriptor Attachment](character-identity-descriptor-attachment.md)
  Defines secondary evidence from strong gendered descriptors attached to canonical characters.
- [Character Pronoun Profile Extraction](character-pronoun-profile-extraction.md)
  Defines separate pronoun-profile extraction for canonical characters.
- [Character Identity Conflict Resolution](character-identity-conflict-resolution.md)
  Defines conflict handling and `unknown` fallback for character identity extraction.
- [Automatic Voice Casting and Override Resolution](automatic-voice-casting-and-override-resolution.md)
  Defines deterministic auto-casting plus user override precedence and fallback behavior.
- [Context-Aware Automatic Voice Casting](context-aware-automatic-voice-casting.md)
  Defines higher-quality automatic casting that uses cast metadata and available voice metadata more intelligently.
- [Cast Voice Override Workflow](cast-voice-override-workflow.md)
  Defines the user-visible narrator/character voice override workflow and its applied playback effect.
- [Multi-Voice Playback Routing](multi-voice-playback-routing.md)
  Umbrella specification for turning narrator/character assignments into routed multi-voice playback behavior.
- [Cast-Aware Speech Range Routing](cast-aware-speech-range-routing.md)
  Defines routed narrator/character speech ranges, resolved voices, and adjacent-range merge behavior.
- [Quoted Dialogue Voice Segmentation](quoted-dialogue-voice-segmentation.md)
  Defines how quoted spoken content remains in character voice while unquoted speaker tags and narration stay narrator speech.
- [Internal Document Serialization Format](internal-document-serialization-format.md)
  Defines the first project-owned serialized internal document format for debugging, testing, and verification.
- [Voice-Routed Progress and Diagnostics](voice-routed-progress-and-diagnostics.md)
  Defines how routed voice use remains visible through progress events and runtime diagnostics.
- [Running-App Multi-Voice Playback Switching](running-app-multi-voice-playback-switching.md)
  Defines the audible narrator-versus-character voice switching behavior users can observe during live playback.
- [Voice Library Metadata and Information Surfacing](voice-library-metadata-and-information-surfacing.md)
  Umbrella specification for app-owned voice metadata and downstream presentation-facing guarantees.
- [Voice Metadata Model and Source Normalization](voice-metadata-model-and-source-normalization.md)
  Defines the app-owned voice metadata fields and normalization from raw engine/catalog metadata.

### Speech Runtime Boundary

- [Speech Runtime Messaging Boundary](speech-runtime-messaging-boundary.md)
  Umbrella specification for the formal runtime boundary between controller code and repeated background speech work.
- [Sendable Runtime DTO Contract](sendable-runtime-dto-contract.md)
  Defines the sendable envelope, allowed value shapes, and forbidden cross-boundary objects for runtime messaging.
- [Speech Runtime Lifecycle and Ownership](speech-runtime-lifecycle-and-ownership.md)
  Defines runtime states, session ownership, generation ownership, and shutdown semantics.
- [Speech Runtime Command Protocol](speech-runtime-command-protocol.md)
  Defines the allowed commands that controller-side code may send into the speech runtime.
- [Speech Runtime Event Protocol](speech-runtime-event-protocol.md)
  Defines the events emitted back out of the speech runtime toward controller-side state derivation.
- [Native Engine Queue Policy](native-engine-queue-policy.md)
  Defines how heavy native engine work must be queued so plugin threading does not block Flutter responsiveness.
- [Platform Capability and Fallback Policy](platform-capability-and-fallback-policy.md)
  Defines how the runtime facade behaves when concurrency or local-engine capability differs by platform.

### Speech Planning and Generation

- [Imported Document Playback](imported-document-playback.md)
  Umbrella specification for imported-document playback behavior.
- [First-Chunk Startup Contract](first-chunk-startup-contract.md)
  Defines the startup contract for first visible playback on imported documents.
- [Imported Playback Responsiveness Policy](imported-playback-responsiveness-policy.md)
  Defines the responsiveness policy that keeps imported playback fast without whole-document pre-generation.
- [Chunk Planning](chunk-planning.md)
  Defines chunk planning inputs, outputs, algorithms, and fallback split rules.
- [Speech Worker Pipeline](speech-worker-pipeline.md)
  Defines background generation stages, worker events, concurrency limits, and cancellation behavior.
- [Generated Audio Cache](generated-audio-cache.md)
  Defines cache keys, storage layout, invalidation rules, and retention behavior for generated speech audio.
- [Synthesis Boundary Policy](synthesis-boundary-policy.md)
  Defines join classes, silence correction, and cacheable finalized chunk behavior.
- [Boundary Candidate Metadata Contract](boundary-candidate-metadata-contract.md)
  Defines the metadata contract required for a chunk to enter boundary correction.
- [Boundary Silence Thresholds](boundary-silence-thresholds.md)
  Defines the initial numeric silence caps used by the boundary policy.
- [Trim-and-Cap Join Correction](trim-and-cap-join-correction.md)
  Defines the default noninitial join-correction algorithm.
- [Initial and Resumed Boundary Handling](initial-and-resumed-boundary-handling.md)
  Defines startup-specific and resumed-playback boundary treatment.
- [Boundary-Corrected Chunk Output and Reuse](boundary-corrected-chunk-output-and-reuse.md)
  Defines corrected-chunk finalization, reuse, and player-gap interaction rules.

### Playback Coordination

- [Playback Coordination](playback-coordination.md)
  Defines controller state, transport behavior, replay semantics, jump handling, and sleep fade behavior.
- [Playback Progress and Jump Mapping](playback-progress-and-jump-mapping.md)
  Defines progress records, timing estimation, future highlighting payloads, and the 30-second jump algorithm.
- [Spoken Text Highlighting and Reading Focus](spoken-text-highlighting-and-reading-focus.md)
  Umbrella specification for spoken selection derivation, display mapping, and reading-focus follow behavior.
- [Spoken Text Selection and Display Mapping](spoken-text-selection-and-display-mapping.md)
  Defines how playback progress becomes a mapped visible spoken selection.
- [Reading Focus Follow Policy](reading-focus-follow-policy.md)
  Defines how the reader viewport follows playback and yields to user scrolling.
- [Playback Quality Instrumentation](playback-quality-instrumentation.md)
  Defines the runtime metrics needed to evaluate smoothness, caching, and chunk-boundary quality.

### Reader Surface and Voice Management UI

- [Primary Reader Surface UI](primary-reader-surface-ui.md)
  Umbrella specification for the simplified reading-first primary surface and integrated advanced voice access.
- [Primary Reader Control Set](primary-reader-control-set.md)
  Defines which reading controls remain visibly dominant on the primary surface.
- [Document Identity Outside Reading Surface](document-identity-outside-reading-surface.md)
  Defines how current-document identity is surfaced without consuming space inside the reading pane.
- [Integrated Secondary Voice Access](integrated-secondary-voice-access.md)
  Defines the integrated secondary affordance for advanced voice and cast controls.
- [Document-Load Cast Processing Overlay](document-load-cast-processing-overlay.md)
  Defines the visible processing and progress state shown while multi-voice document analysis is running.
- [Multi-Voice Mode Toggle And Cast Entrypoint](multi-voice-mode-toggle-and-cast-entrypoint.md)
  Defines the user control for multi-voice mode and the primary-surface cast-management entry behavior when that mode is active.
- [Feedback Surface Contrast Readability](feedback-surface-contrast-readability.md)
  Defines the minimum readable contrast requirements for surfaced in-app feedback while broader feedback UX redesign remains pending.
- [Reader Options And Secondary Settings UI](reader-options-and-secondary-settings-ui.md)
  Umbrella specification for the Reader Options secondary settings and diagnostics surface.
- [Reader Preferences Controls](reader-preferences-controls.md)
  Defines the Reader Options controls for voice speed, reading font, and reading scale.
- [Sleep Timer And Timing Surface](sleep-timer-and-timing-surface.md)
  Defines how sleep-timer controls and timing-model information are surfaced in Reader Options.
- [Reader Diagnostics And Source Panels](reader-diagnostics-and-source-panels.md)
  Defines the Reader Options panels for TTS trace inspection and document-source metadata.
- [Voice Library and Cast Management UI](voice-library-and-cast-management-ui.md)
  Umbrella specification for advanced voice-library and cast-management UI structure.
- [Voice Library Row and Information Affordance](voice-library-row-and-information-affordance.md)
  Defines the voice-library row hierarchy, direct quality surfacing, and info affordance behavior.
- [Cast Management Dialog Structure](cast-management-dialog-structure.md)
  Defines the narrator/character voice-management dialog structure and override-state presentation.
- [Voice Management Dialog Contrast And Readability](voice-management-dialog-contrast-and-readability.md)
  Defines the minimum readable contrast requirements for the narrator/character voice-management dialog.
- [Theme And Appearance Modes UI](theme-and-appearance-modes-ui.md)
  Umbrella specification for surfaced appearance-mode selection and follow-system behavior.
- [Appearance Mode Selection And System Following](appearance-mode-selection-and-system-following.md)
  Defines the running-app light, dark, and follow-system appearance behavior.
- [Follow-Along Reading Surface UI](follow-along-reading-surface-ui.md)
  Umbrella specification for the visible follow-along reading-surface UI.
- [Spoken Highlight Visual Presentation](spoken-highlight-visual-presentation.md)
  Defines the visible styling and fallback precision of the spoken highlight.
- [Reading Surface Contrast And Highlight Legibility](reading-surface-contrast-and-highlight-legibility.md)
  Defines readable reading-surface contrast and highlight-preserving text legibility across appearance modes.
- [Follow-Along User Scroll Interaction](follow-along-user-scroll-interaction.md)
  Defines how auto-follow yields to manual scrolling and how re-centering is exposed.

### Reader Session and Live Input

- [Reader Session Continuity and Live Input](reader-session-continuity-and-live-input.md)
  Umbrella specification for remembered file-backed reader state, startup resume, and watched-file live input behavior.
- [File-Backed Document Restore And Directory Continuity](file-backed-document-restore-and-directory-continuity.md)
  Defines remembering the last file-backed document, restoring it on startup, and preserving the last used directory.
- [Remembered Reading Position And Startup Resume](remembered-reading-position-and-startup-resume.md)
  Defines restoring the user's last heard position when the remembered document is reopened.
- [Watched-File Session Refresh](watched-file-session-refresh.md)
  Defines live-input watched-file refresh inside the running app.
- [Live Input And File Menu UI](live-input-and-file-menu-ui.md)
  Umbrella specification for live-input menu placement and surfaced playback semantics.
- [Live Input Menu Placement And Playing-State Continuation](live-input-menu-placement-and-playing-state-continuation.md)
  Defines File-menu access to live input and the playing-versus-paused behavior after watched-file refresh.

### Repository Onboarding and Community

- [Repository Readme and GitHub Community Files](repository-readme-and-github-community-files.md)
  Defines the required root onboarding docs and GitHub community-health files for the repository surface.

### Audio Export and Headless Execution

- [Audio Export and Headless Execution](audio-export-and-headless-execution.md)
  Umbrella specification for saving spoken audio and running the same synthesis pipeline without the normal UI.
- [Audio Export Assembly](audio-export-assembly.md)
  Defines ordered finalized-chunk assembly into one exported WAV plus export metadata sidecar.
- [Command-Line Mode Selection](command-line-mode-selection.md)
  Defines startup argument parsing and mode selection across UI, headless export, and probe modes.
- [Headless Synthesis Session](headless-synthesis-session.md)
  Defines file import, voice/rate selection, export sequencing, and process exit behavior in headless mode.
- [In-App Audio Export Workflow](in-app-audio-export-workflow.md)
  Defines the interactive app workflow for saving spoken audio.
- [Speech QA Debug Tooling](speech-qa-debug-tooling.md)
  Defines phrase probes, sentence probes, waveform comparison, durable trace logs, and stable speech-QA artifact storage.
