# Document and Speech Pipeline

Reconciled: October 26, 2026; RC2 implementation through feature head 2734b47
Status: Incremental preparation and checkpoint replay implemented; native/release/audio acceptance pending

## Implemented structure and limitations

`DocumentImportService` retains parsing and semantic rules for text/Markdown, HTML, EPUB, PDF, DOCX and RTF. Interactive intake calls `DocumentPreparationSupervisor`: the main-isolate controller owns intake/revision state; pure Dart workers perform decode/decompression, parsing, normalization, mapping, annotations, heuristic attribution, cast construction, pronunciation artifacts, display HTML and word spans. Interactive range intake publishes immutable, contiguous prepared fragments as they become ready; it does not wait for every later range before exposing the first range. The controller keeps a bounded reading-ahead window (up to three unconsumed ranges) and exposes per-stage preparation progress. Each callback carries operation/document/watch identity and publication sequence; stale outcomes are discarded. This permits early display and downstream planning while later preparation continues, but does not itself prove first-audio timing, uninterrupted playback, or that expensive source adapters are universally incremental.

The supervisor admits one active operation and one latest pending descriptor. File byte acquisition occurs only after admission; access recovery remains a small platform bridge. Replacement cancels pending requests and suppresses old outcomes immediately. A native PDF extraction runs through pdfrx's existing native worker and owns document disposal in `finally`; only raw text/character rectangles cross into the pure worker, where a data-only page adapter runs pdfrx's existing reading-order formatter; the Dart supervisor waits for that adapter to drain before admitting the replacement. Pure Dart workers are killed on cancellation/timeout and their exit is awaited. A two-minute default deadline emits a terminal timeout; non-cancellable file/native bridges may keep the active slot until they drain. Shutdown stops intake, cancels pending work and awaits that drain. `ReaderController.shutdownPreparation()` exposes awaitable preparation cleanup; synchronous Flutter `dispose()` invalidates identities immediately and starts cleanup, without claiming that native teardown has already finished.

Requests carry owner, revision, operation kind and optional watch session. Success, failure and cleanup are accepted only for the current identity, including after engine-stop, bookmark and access awaits. File watchers have separate session ownership. The controller preserves the previously displayed document while preparing its replacement; `isDisplayReady`, `isDocumentPrepared` and transport-derived `isAudioReady` are distinct. `startPlayback` refuses entry during preparation. Display and preparation become ready together for a new document in this slice. The published `preparedDocumentRevision` and `preparationOwnerId` identify the accepted graph for subsequent resource ownership. Cast voice IDs remain available through the existing assignment resolver; resident-resource readiness belongs to P2, not these preparation flags.

`ReaderDocument.preparedSnapshot` retains computed HTML/text/word spans and freezes nested collections on the worker. The typed graph transfers directly on worker exit; UI-side JSON decode and repeated analysis are avoided. The existing `radoc-v1` writer remains for legacy artifact operations. Normal Open Document picker intake accepts `.radoc` v1 and v2 through the serialization service, bypassing ordinary source-import analysis; malformed or unsupported files are refused with compatible-version re-export guidance. This picker path restores the serialized `ReaderDocument` for editing/reading, but does not restore native engine handles or resident synthesis resources. The instrumented `.radoc-v2` codec remains a distinct data-artifact API: it serializes the graph plus caller-supplied revision and complete cast assignment/resource-reference records, and its decoder returns an immutable JSON snapshot rather than an application document. Neither v1 nor v2 is a complete multi-range checkpoint export format: PDF/asset/native resources are not generally embedded by the v2 snapshot, and multi-range export/reopen remains incomplete. See [RC2 design #83](https://github.com/kellyjanderson/readaloud/issues/83), [reusable persistence slice #90](https://github.com/kellyjanderson/readaloud/issues/90), and [picker intake slice #101](https://github.com/kellyjanderson/readaloud/issues/101).

Automatic `ReaderDocumentRepository` checkpoints are separate from user-exported `.radoc` files. Each prepared range is serialized to an immutable, size-bounded file and committed before the producer receives credit for another range. A checksummed manifest records source revision, dependency/schema versions, generation and contiguous source/word/segment coverage; only successful producer EOF marks it complete. Reopen replays a complete checkpoint range by range and can skip source acquisition and worker analysis for the same stable source revision. Captured text/bytes receive a content revision; the current file-backed path has no trusted immutable revision, so it conservatively misses the cache. Captured-source revision hashing currently reads the full captured input before lookup, so cache lookup does not remove that hashing cost. A missing, corrupt or incompatible manifest is a cache miss. Corrupt ranges invalidate the generation and fail before later publication; retry rebuilds from source rather than trusting or resuming a prefix. Partial checkpoints can contribute valid ranges only where the producer can continue consistently; they are never treated as complete/exportable books. Identity migration from provisional source identity to acquired-byte identity is limited to a complete checkpoint with a qualifying acquisition receipt. See #90 for implementation and remaining limitations.

Preparation exposes controller APIs for cancellation and retry (`cancelDocumentPreparation`, `retryDocumentPreparation`), stage progress, and bounded range consumption. Cancellation suppresses stale publication and releases a paused consumer credit; retries start a new operation revision. The normal picker path also refuses malformed `.radoc` input while preserving the active document. These APIs and tests establish software behavior only; they do not establish native app acceptance, release readiness or audible output quality.

`SpeechAnnotation` also represents optional span-level delivery intent (`whispered`, `shouted`, `spoken`, `sung`) and inflection intent (`rising`, `falling`, `level`). Each intent carries explicit-source/user provenance and confidence; unknown remains absent. The inference service accepts caller-supplied explicit intents with validated speech-word ranges; it does not infer performance or emotion from prose, punctuation or dialogue tags. Importers and UI do not yet supply these intents automatically. V2 preserves these canonical values and rejects invalid vocabulary, provenance, confidence or spans during decode; V1 omits the new kinds to preserve its existing output. Voice-session realization retains each intent and records `unsupported` with `engine_default` fallback in session/segment diagnostics for current engine adapters; this does not claim or alter acoustic delivery. See [R3 slice #79](https://github.com/kellyjanderson/readaloud/issues/79).

Residual limits are explicit: the controller constructs the small fixed bundled sample synchronously at startup; later sample requests use the worker. `loadDocument` accepts an already constructed complete graph. Headless export/probe runners still call the importer directly and do not host the interactive range/checkpoint lifecycle. An injected importer is a controllable test/legacy adapter on the caller isolate, not production-worker proof. Runtime realization and cast-aware chunk planning run in the resident planning worker, with separate playback/export owners and bounded returned windows. Framework HTML layout remains on Flutter. RC2 has bounded local implementation evidence, but current integrated native build/app behavior, launch timing, emitted-audio continuity and human listening remain unqualified; no native, release or audio acceptance is claimed. See #83 and #90 for current gates.

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
