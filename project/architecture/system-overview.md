# System Overview

Reconciled: October 25, 2026; P4 production lineage 295677e
Status: Implemented source with bounded P0–P3 evidence; integrated P4/FINAL acceptance pending

## Implemented structure and limitations

Read Aloud is a local Flutter document reader. The native default engine path uses Kokoro; platform fallbacks exist, but macOS is the project’s functional target. This is not a claim of fresh installed-app verification.

The main entry selects UI or headless execution. `ReaderController` owns UI-facing transport, document intake, voice settings, restore, watched-file reload and follow-along state. `ReaderDocument` aggregates display/speech models, position mappings, annotations, pronunciation, character registry and document voice attribution. Compatibility text/HTML views remain in use.

Interactive import runs decode/normalization/semantic preparation in a supervised pure Dart worker, then transfers one frozen completed graph. Resident pure Dart planning and tokenization workers own render-ahead realization, cast routes and token preparation. The controller accepts bounded results on the main isolate using document, assignment and playback identities. One supervised resident synthesis isolate owns the model session and validated voice vectors; the native plugin serializes ONNX calls. Default boundary correction and export assembly run in explicit worker contexts.

Display readiness, completed document preparation, prepared resources and finalized audio lead are distinct. Playback uses bounded contiguous lead and single-owner native admission shared with export. Prepared cast references retain attribution/assignment provenance and content fingerprints; ordinary speaker transitions select resident vectors. P4 records requested choices separately from engine-acknowledged effective choices. Active edits preserve current audio until explicit Apply and replay current chunk or next Play; this fallback may repeat a partial chunk and makes no seamless-tail claim. Immutable raw/corrected artifacts and generation-owned pins protect publication/lifetime. See the component pages and [evidence index](README.md#evidence-and-acceptance-limits) for exact limits.

## Source and tests

- [main.dart](../../lib/main.dart)
- [reader_controller.dart](../../lib/src/controllers/reader_controller.dart)
- [reader_document.dart](../../lib/src/models/reader_document.dart)
- [widget_test.dart](../../test/widget_test.dart)
- [reader_controller_playback_test.dart](../../test/reader_controller_playback_test.dart)

Tests listed here are evidence locations, not a claim that every case was rerun for this page. The pinned native arm64 Flutter 3.41.5 / Dart 3.11.3 toolchain is runnable; the earlier Intel SDK failure is historical. See the [evidence index](README.md#evidence-and-acceptance-limits) for bounded source/native results.

## Design and remaining acceptance

See [prepared document runtime ACD](https://github.com/kellyjanderson/readaloud/issues/48) and its [implementation plan](https://github.com/kellyjanderson/readaloud/issues/48). Historical design prose is preserved in the [architecture snapshot](../archive/architecture/2026-10-24/system-overview.md).

## Retained child contracts

These legacy contracts describe intended behavior and acceptance; `final` denotes refinement, not verified implementation. New changes use GitHub design and slice issues; final architecture stays in this repository.

- [app wide semantic theme token adoption](../specifications/app-wide-semantic-theme-token-adoption.md)
- [appearance mode selection and system following](../specifications/appearance-mode-selection-and-system-following.md)
- [append only forward playback queue](../specifications/append-only-forward-playback-queue.md)
- [audio export assembly](../specifications/audio-export-assembly.md)
- [boundary candidate metadata contract](../specifications/boundary-candidate-metadata-contract.md)
- [boundary corrected chunk output and reuse](../specifications/boundary-corrected-chunk-output-and-reuse.md)
- [boundary intent realization](../specifications/boundary-intent-realization.md)
- [boundary silence thresholds](../specifications/boundary-silence-thresholds.md)
- [buffered lead time and underrun policy](../specifications/buffered-lead-time-and-underrun-policy.md)
- [cast management dialog structure](../specifications/cast-management-dialog-structure.md)
- [chunk planning](../specifications/chunk-planning.md)
- [command line mode selection](../specifications/command-line-mode-selection.md)
- [compact voice domain control and word count de emphasis](../specifications/compact-voice-domain-control-and-word-count-de-emphasis.md)
- [discourse role annotation model](../specifications/discourse-role-annotation-model.md)
- [display document](../specifications/display-document.md)
- [document identity outside reading surface](../specifications/document-identity-outside-reading-surface.md)
- [document load cast processing overlay](../specifications/document-load-cast-processing-overlay.md)
- [document replacement playback reset and stale event rejection](../specifications/document-replacement-playback-reset-and-stale-event-rejection.md)
- [document time pronunciation planner](../specifications/document-time-pronunciation-planner.md)
- [docx document normalization](../specifications/docx-document-normalization.md)
- [editorial typography role application](../specifications/editorial-typography-role-application.md)
- [emphasis candidate model](../specifications/emphasis-candidate-model.md)
- [emphasis intent realization](../specifications/emphasis-intent-realization.md)
- [engine intent translation policy](../specifications/engine-intent-translation-policy.md)
- [engine pronunciation translation policy](../specifications/engine-pronunciation-translation-policy.md)
- [epub document normalization](../specifications/epub-document-normalization.md)
- [feedback surface contrast readability](../specifications/feedback-surface-contrast-readability.md)
- [file backed document restore and directory continuity](../specifications/file-backed-document-restore-and-directory-continuity.md)
- [first chunk startup contract](../specifications/first-chunk-startup-contract.md)
- [follow along user scroll interaction](../specifications/follow-along-user-scroll-interaction.md)
- [generated audio cache](../specifications/generated-audio-cache.md)
- [headless synthesis session](../specifications/headless-synthesis-session.md)
- [html document normalization](../specifications/html-document-normalization.md)
- [import diagnostics taxonomy](../specifications/import-diagnostics-taxonomy.md)
- [import failure and partial success semantics](../specifications/import-failure-and-partial-success-semantics.md)
- [import source acquisition and fingerprinting](../specifications/import-source-acquisition-and-fingerprinting.md)
- [import structural cleanup and visible content preservation](../specifications/import-structural-cleanup-and-visible-content-preservation.md)
- [imported playback responsiveness policy](../specifications/imported-playback-responsiveness-policy.md)
- [in app audio export workflow](../specifications/in-app-audio-export-workflow.md)
- [initial and resumed boundary handling](../specifications/initial-and-resumed-boundary-handling.md)
- [integrated secondary voice access](../specifications/integrated-secondary-voice-access.md)
- [internal document serialization format](../specifications/internal-document-serialization-format.md)
- [line wrap and paragraph recovery](../specifications/line-wrap-and-paragraph-recovery.md)
- [live input menu placement and playing state continuation](../specifications/live-input-menu-placement-and-playing-state-continuation.md)
- [lossy text common heuristic grouping](../specifications/lossy-text-common-heuristic-grouping.md)
- [markup and archive common structural normalization](../specifications/markup-and-archive-common-structural-normalization.md)
- [multi voice mode toggle and cast entrypoint](../specifications/multi-voice-mode-toggle-and-cast-entrypoint.md)
- [narration state](../specifications/narration-state.md)
- [native engine queue policy](../specifications/native-engine-queue-policy.md)
- [normalized import result envelope](../specifications/normalized-import-result-envelope.md)
- [normalized layer compatibility and migration](../specifications/normalized-layer-compatibility-and-migration.md)
- [normalized layer shared identity and metadata](../specifications/normalized-layer-shared-identity-and-metadata.md)
- [pause and break taxonomy](../specifications/pause-and-break-taxonomy.md)
- [pdf extracted text normalization](../specifications/pdf-extracted-text-normalization.md)
- [persistent file access for startup restore](../specifications/persistent-file-access-for-startup-restore.md)
- [plain and shared text normalization](../specifications/plain-and-shared-text-normalization.md)
- [platform capability and fallback policy](../specifications/platform-capability-and-fallback-policy.md)
- [playback coordination](../specifications/playback-coordination.md)
- [playback progress and jump mapping](../specifications/playback-progress-and-jump-mapping.md)
- [playback quality instrumentation](../specifications/playback-quality-instrumentation.md)
- [position map](../specifications/position-map.md)
- [prepared document and buffered playback](https://github.com/kellyjanderson/readaloud/issues/48)
- [primary reader control set](../specifications/primary-reader-control-set.md)
- [pronunciation artifact model](../specifications/pronunciation-artifact-model.md)
- [pronunciation candidate model](../specifications/pronunciation-candidate-model.md)
- [pronunciation fallback and traceability](../specifications/pronunciation-fallback-and-traceability.md)
- [pronunciation realization precedence](../specifications/pronunciation-realization-precedence.md)
- [reader diagnostics and source panels](../specifications/reader-diagnostics-and-source-panels.md)
- [reader options sectioned information hierarchy](../specifications/reader-options-sectioned-information-hierarchy.md)
- [reader preferences controls](../specifications/reader-preferences-controls.md)
- [reading surface contrast and highlight legibility](../specifications/reading-surface-contrast-and-highlight-legibility.md)
- [realization window policy](../specifications/realization-window-policy.md)
- [remembered reading position and startup resume](../specifications/remembered-reading-position-and-startup-resume.md)
- [repository readme and github community files](../specifications/repository-readme-and-github-community-files.md)
- [rtf flattened text normalization](../specifications/rtf-flattened-text-normalization.md)
- [running app uninterrupted speech under follow along load](../specifications/running-app-uninterrupted-speech-under-follow-along-load.md)
- [say as candidate model](../specifications/say-as-candidate-model.md)
- [secondary surface component family consistency](../specifications/secondary-surface-component-family-consistency.md)
- [segmented transport capsule](../specifications/segmented-transport-capsule.md)
- [sendable runtime dto contract](../specifications/sendable-runtime-dto-contract.md)
- [sleep timer and timing surface](../specifications/sleep-timer-and-timing-surface.md)
- [speech annotation envelope model](../specifications/speech-annotation-envelope-model.md)
- [speech document](../specifications/speech-document.md)
- [speech qa debug tooling](../specifications/speech-qa-debug-tooling.md)
- [speech runtime command protocol](../specifications/speech-runtime-command-protocol.md)
- [speech runtime event protocol](../specifications/speech-runtime-event-protocol.md)
- [speech runtime lifecycle and ownership](../specifications/speech-runtime-lifecycle-and-ownership.md)
- [speech worker pipeline](../specifications/speech-worker-pipeline.md)
- [spoken highlight visual presentation](../specifications/spoken-highlight-visual-presentation.md)
- [transient feedback toast behavior](../specifications/transient-feedback-toast-behavior.md)
- [trim and cap join correction](../specifications/trim-and-cap-join-correction.md)
- [tts runtime chunk request derivation](../specifications/tts-runtime-chunk-request-derivation.md)
- [uninterrupted audio primary channel](../specifications/uninterrupted-audio-primary-channel.md)
- [voice library direct character assignment](../specifications/voice-library-direct-character-assignment.md)
- [voice library row and information affordance](../specifications/voice-library-row-and-information-affordance.md)
- [voice management dialog contrast and readability](../specifications/voice-management-dialog-contrast-and-readability.md)
- [voice preview button behavior](../specifications/voice-preview-button-behavior.md)
- [voice session pronunciation realization](../specifications/voice-session-pronunciation-realization.md)
- [voice session realization envelope](../specifications/voice-session-realization-envelope.md)
- [watched file session refresh](../specifications/watched-file-session-refresh.md)
