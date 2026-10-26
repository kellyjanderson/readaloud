# Document and Speech Pipeline

Reconciled: October 25, 2026; P4 production lineage 295677e
Status: Implemented P1 preparation/P3 planning; P4/FINAL integrated acceptance pending

## Implemented structure and limitations

`DocumentImportService` retains parsing and semantic rules for text/Markdown, HTML, EPUB, PDF, DOCX and RTF. Interactive intake now calls `DocumentPreparationSupervisor`: the main-isolate controller owns intake/revision state; a pure Dart worker owns decode/decompression, parse, normalization, mapping, annotations, heuristic attribution, cast construction, pronunciation artifacts, display HTML, word spans, freezing and JSON serialization. No partially analyzed new document is published.

The supervisor admits one active operation and one latest pending descriptor. File byte acquisition occurs only after admission; access recovery remains a small platform bridge. Replacement cancels pending requests and suppresses old outcomes immediately. A native PDF extraction runs through pdfrx's existing native worker and owns document disposal in `finally`; only raw text/character rectangles cross into the pure worker, where a data-only page adapter runs pdfrx's existing reading-order formatter; the Dart supervisor waits for that adapter to drain before admitting the replacement. Pure Dart workers are killed on cancellation/timeout and their exit is awaited. A two-minute default deadline emits a terminal timeout; non-cancellable file/native bridges may keep the active slot until they drain. Shutdown stops intake, cancels pending work and awaits that drain. `ReaderController.shutdownPreparation()` exposes awaitable preparation cleanup; synchronous Flutter `dispose()` invalidates identities immediately and starts cleanup, without claiming that native teardown has already finished.

Requests carry owner, revision, operation kind and optional watch session. Success, failure and cleanup are accepted only for the current identity, including after engine-stop, bookmark and access awaits. File watchers have separate session ownership. The controller preserves the previously displayed document while preparing its replacement; `isDisplayReady`, `isDocumentPrepared` and transport-derived `isAudioReady` are distinct. `startPlayback` refuses entry during preparation. Display and preparation become ready together for a new document in this slice. The published `preparedDocumentRevision` and `preparationOwnerId` identify the accepted graph for subsequent resource ownership. Cast voice IDs remain available through the existing assignment resolver; resident-resource readiness belongs to P2, not these preparation flags.

`ReaderDocument.preparedSnapshot` retains already computed HTML/text/word spans and freezes nested collections on the worker. The typed graph transfers directly on worker exit: there is no UI-side JSON decode or repeated analysis. The existing `.radoc` (`radoc-v1`) serialization is unchanged, includes PDF bytes as base64 and remains write-only. The separate `.radoc-v2` artifact codec serializes the instrumented graph plus caller-supplied document revision, a complete assignment for every cast registry entry and a matching prepared voice reference for each assignment. Its decoder returns a recursively immutable JSON snapshot only; it does not recreate a `ReaderDocument`, reopen a source, hydrate runtime/cache resources or include embedded PDF/asset bytes or native handles. Identity, revision, cast coverage and reference consistency are checked during decode. This is an inspection/data round trip, not an application restore format. `SpeechAnnotation` also represents optional span-level delivery intent (`whispered`, `shouted`, `spoken`, `sung`) and inflection intent (`rising`, `falling`, `level`). Each intent carries its own explicit-source/user provenance and confidence; unknown remains absent. The inference service accepts caller-supplied explicit intents with validated speech-word ranges; it does not infer performance or emotion from prose, punctuation or dialogue tags. Importers and UI do not yet supply these intents automatically. V2 preserves these canonical values and rejects invalid vocabulary, provenance, confidence or spans during decode; V1 omits the new kinds to preserve its existing output. Voice-session realization retains each intent and records `unsupported` with `engine_default` fallback in the session/segment diagnostics for every current engine adapter; it does not claim or alter acoustic delivery. Intent data participates in realization identity. This is model/serialization/fallback evidence, not audible delivery acceptance. See [R3 slice #79](https://github.com/kellyjanderson/readaloud/issues/79). `writeToFile` for v1 performs JSON encoding in an isolate.

Residual limits are explicit: the controller constructs the small fixed bundled sample synchronously at startup; later sample requests use the worker. `loadDocument` accepts an already constructed complete graph. Headless export/probe runners still call the importer directly and do not host an interactive reader. An injected importer is a controllable test/legacy adapter on the caller isolate, not production-worker proof. Runtime realization and cast-aware chunk planning now run in the resident planning worker, with separate playback/export owners and bounded returned windows. Framework HTML layout remains on Flutter. P1 records bounded running-app preparation/input/publication proof; source tests and event-loop heartbeats do not establish universal responsiveness, native cleanup or audio continuity. Later P4 frame/input checks remain pending.

## Source and tests

- [document_preparation_supervisor.dart](../../lib/src/services/document_preparation_supervisor.dart)
- [document_preparation_supervisor_test.dart](../../test/document_preparation_supervisor_test.dart)
- [document_import_service.dart](../../lib/src/services/document_import_service.dart)
- [reader_controller.dart](../../lib/src/controllers/reader_controller.dart)
- [chunk_planner_service.dart](../../lib/src/services/chunk_planner_service.dart)
- [reader_document_serialization_service.dart](../../lib/src/services/reader_document_serialization_service.dart)
- [instrumented_document_artifact_codec.dart](../../lib/src/services/instrumented_document_artifact_codec.dart)
- [document_import_service_test.dart](../../test/document_import_service_test.dart)
- [chunk_planner_service_test.dart](../../test/chunk_planner_service_test.dart)
- [reader_document_serialization_service_test.dart](../../test/reader_document_serialization_service_test.dart)
- [instrumented_document_artifact_codec_test.dart](../../test/instrumented_document_artifact_codec_test.dart)
- [performance_intent_test.dart](../../test/performance_intent_test.dart)

The focused preparation tests cover worker artifact equality, nested immutability, PDF handoff, queue bounds, timeout, exit, native drain and caller event-loop progress. Controller tests cover overlapping success/failure, readiness, stale publication after engine stop and cancelled watcher installation. Exact run/native evidence is recorded in [P1](https://github.com/kellyjanderson/readaloud/issues/50); use the pinned native arm64 SDK documented in development guidance.

## Design and remaining acceptance

See [prepared document runtime ACD](https://github.com/kellyjanderson/readaloud/issues/48) and its [implementation plan](https://github.com/kellyjanderson/readaloud/issues/48). Historical design prose is preserved in the [architecture snapshot](../archive/architecture/2026-10-24/document-speech-pipeline.md).

## Retained child contracts

These legacy contracts describe intended behavior and acceptance; `final` denotes refinement, not verified implementation. New changes use GitHub design and slice issues; final architecture stays in this repository.

- [audio export assembly](../specifications/audio-export-assembly.md)
- [boundary candidate metadata contract](../specifications/boundary-candidate-metadata-contract.md)
- [boundary corrected chunk output and reuse](../specifications/boundary-corrected-chunk-output-and-reuse.md)
- [boundary intent realization](../specifications/boundary-intent-realization.md)
- [boundary silence thresholds](../specifications/boundary-silence-thresholds.md)
- [chunk planning](../specifications/chunk-planning.md)
- [command line mode selection](../specifications/command-line-mode-selection.md)
- [discourse role annotation model](../specifications/discourse-role-annotation-model.md)
- [display document](../specifications/display-document.md)
- [document time pronunciation planner](../specifications/document-time-pronunciation-planner.md)
- [docx document normalization](../specifications/docx-document-normalization.md)
- [emphasis candidate model](../specifications/emphasis-candidate-model.md)
- [emphasis intent realization](../specifications/emphasis-intent-realization.md)
- [engine intent translation policy](../specifications/engine-intent-translation-policy.md)
- [engine pronunciation translation policy](../specifications/engine-pronunciation-translation-policy.md)
- [epub document normalization](../specifications/epub-document-normalization.md)
- [generated audio cache](../specifications/generated-audio-cache.md)
- [headless synthesis session](../specifications/headless-synthesis-session.md)
- [html document normalization](../specifications/html-document-normalization.md)
- [import diagnostics taxonomy](../specifications/import-diagnostics-taxonomy.md)
- [import failure and partial success semantics](../specifications/import-failure-and-partial-success-semantics.md)
- [import source acquisition and fingerprinting](../specifications/import-source-acquisition-and-fingerprinting.md)
- [import structural cleanup and visible content preservation](../specifications/import-structural-cleanup-and-visible-content-preservation.md)
- [in app audio export workflow](../specifications/in-app-audio-export-workflow.md)
- [initial and resumed boundary handling](../specifications/initial-and-resumed-boundary-handling.md)
- [line wrap and paragraph recovery](../specifications/line-wrap-and-paragraph-recovery.md)
- [lossy text common heuristic grouping](../specifications/lossy-text-common-heuristic-grouping.md)
- [markup and archive common structural normalization](../specifications/markup-and-archive-common-structural-normalization.md)
- [narration state](../specifications/narration-state.md)
- [normalized import result envelope](../specifications/normalized-import-result-envelope.md)
- [normalized layer compatibility and migration](../specifications/normalized-layer-compatibility-and-migration.md)
- [normalized layer shared identity and metadata](../specifications/normalized-layer-shared-identity-and-metadata.md)
- [pause and break taxonomy](../specifications/pause-and-break-taxonomy.md)
- [pdf extracted text normalization](../specifications/pdf-extracted-text-normalization.md)
- [plain and shared text normalization](../specifications/plain-and-shared-text-normalization.md)
- [playback coordination](../specifications/playback-coordination.md)
- [playback progress and jump mapping](../specifications/playback-progress-and-jump-mapping.md)
- [playback quality instrumentation](../specifications/playback-quality-instrumentation.md)
- [position map](../specifications/position-map.md)
- [pronunciation artifact model](../specifications/pronunciation-artifact-model.md)
- [pronunciation candidate model](../specifications/pronunciation-candidate-model.md)
- [pronunciation fallback and traceability](../specifications/pronunciation-fallback-and-traceability.md)
- [pronunciation realization precedence](../specifications/pronunciation-realization-precedence.md)
- [realization window policy](../specifications/realization-window-policy.md)
- [rtf flattened text normalization](../specifications/rtf-flattened-text-normalization.md)
- [say as candidate model](../specifications/say-as-candidate-model.md)
- [speech annotation envelope model](../specifications/speech-annotation-envelope-model.md)
- [speech document](../specifications/speech-document.md)
- [speech qa debug tooling](../specifications/speech-qa-debug-tooling.md)
- [speech worker pipeline](../specifications/speech-worker-pipeline.md)
- [trim and cap join correction](../specifications/trim-and-cap-join-correction.md)
- [tts runtime chunk request derivation](../specifications/tts-runtime-chunk-request-derivation.md)
- [voice session pronunciation realization](../specifications/voice-session-pronunciation-realization.md)
- [voice session realization envelope](../specifications/voice-session-realization-envelope.md)
