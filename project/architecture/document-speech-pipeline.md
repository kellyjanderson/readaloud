# Document and Speech Pipeline

Reconciled: October 26, 2026; RC2 #90 R5 source changes, with native acceptance separate
Status: Incremental preparation and checkpoint replay implemented; native/release/audio acceptance pending

## Implemented structure and limitations

`DocumentImportService` retains parsing and semantic rules for text/Markdown, HTML, EPUB, PDF, DOCX and RTF. Interactive intake calls `DocumentPreparationSupervisor`: the main-isolate controller owns intake/revision state; pure Dart workers perform decode/decompression, parsing, normalization, mapping, annotations, heuristic attribution, cast construction, pronunciation artifacts, display HTML and word spans. Interactive range intake publishes immutable, contiguous prepared fragments as they become ready; it does not wait for every later range before exposing the first range. The controller keeps a bounded reading-ahead window (up to eight unconsumed ranges) and exposes per-stage preparation progress. A full window pauses acquisition, parsing and persistence with an explicit waiting state; a confirmed final publication bypasses credit waiting so EOF can complete even at exact capacity. Text/container intake keeps one bounded successor to prove EOF independently of dialogue attribution lookahead. Native PDF pages retain demand extraction, so absence of a successor halo does not claim EOF. Cancellation marks outstanding stages cancelled; publication callbacks recheck revision ownership after notifying listeners before installing a credit wait. Waiting stages do not animate progress bars, and completed source stages disappear after successful EOF. Each callback carries operation/document/watch identity and publication sequence; stale outcomes are discarded. This permits early display and downstream planning while later preparation continues, but does not itself prove first-audio timing, uninterrupted playback, or that expensive source adapters are universally incremental.

The supervisor admits one active operation and one latest pending descriptor. File byte acquisition occurs only after admission; access recovery remains a small platform bridge. Replacement cancels pending requests and suppresses old outcomes immediately. A native PDF extraction runs through pdfrx's existing native worker and owns document disposal in `finally`; only raw text/character rectangles cross into the pure worker, where a data-only page adapter runs pdfrx's existing reading-order formatter; the Dart supervisor waits for that adapter to drain before admitting the replacement. Pure Dart workers are killed on cancellation/timeout and their exit is awaited. A two-minute default deadline emits a terminal timeout; non-cancellable file/native bridges may keep the active slot until they drain. Shutdown stops intake, cancels pending work and awaits that drain. `ReaderController.shutdownPreparation()` exposes awaitable preparation cleanup; synchronous Flutter `dispose()` invalidates identities immediately and starts cleanup, without claiming that native teardown has already finished.

Requests carry owner, revision, operation kind and optional watch session. Success, failure and cleanup are accepted only for the current identity, including after engine-stop, bookmark and access awaits. File watchers have separate session ownership. The controller preserves the previously displayed document while preparing its replacement; `isDisplayReady`, `isDocumentPrepared` and transport-derived `isAudioReady` are distinct. `startPlayback` refuses entry during preparation. Display and preparation become ready together for a new document in this slice. The published `preparedDocumentRevision` and `preparationOwnerId` identify the accepted graph for subsequent resource ownership. Cast voice IDs remain available through the existing assignment resolver; resident-resource readiness belongs to P2, not these preparation flags.

`ReaderDocument.preparedSnapshot` retains computed HTML/text/word spans and freezes nested collections on the worker. The typed graph transfers directly on worker exit; UI-side JSON decode and repeated analysis are avoided. Normal Open Document picker intake accepts `.radoc` v1, v2 and v3 through the serialization service, bypassing ordinary source-import analysis; malformed or unsupported files are refused with compatible-version re-export guidance. V3 additionally carries the shared Character state, selected voice and Reset tombstone; v2 optionally carries validated explicit cast voice choices; a fresh preference store restores them, while existing local choices take precedence over an older exported snapshot. Validation precedes document/preference mutation. Native handles/resources are not restored. The instrumented `.radoc-v2` codec remains a separate immutable inspection API. It is distinct from the normal application's `.radoc` restore path. See [RC2 design #83](https://github.com/kellyjanderson/readaloud/issues/83), [persistence #90](https://github.com/kellyjanderson/readaloud/issues/90), and [picker intake #101](https://github.com/kellyjanderson/readaloud/issues/101).

Automatic `ReaderDocumentRepository` checkpoints are separate from user-exported `.radoc` files. Each prepared range is serialized to an immutable, size-bounded file and committed before the producer receives credit for another range. A checksummed manifest records source revision, dependency/schema versions, generation and contiguous source/word/segment coverage; only successful producer EOF marks it complete. A bounded manifest lookup admits complete-checkpoint replay without source acquisition or repeated worker analysis. Directly captured text/bytes retain content revisions and full-input hashing before lookup; callback-acquired inputs conservatively miss because they lack a stable pre-admission revision.

For local macOS regular files, the source owner records canonical symlink target plus device/inode/inode generation, size, nanosecond mtime/ctime and mode. Dart's millisecond `FileStat` cannot distinguish every ordinary rewrite; a fixed-size `/usr/bin/stat` probe supplies the higher-resolution receipt without reading book bytes. Controller identity probes share one serialized lane with captured-input hashing; the supervisor's one active operation owns subsequent validation. A probe has a one-second deadline and kills/drains its subprocess on timeout. Missing or unsupported metadata misses conservatively. File restore bookmarks are prepared before capturing this revision, because bookmark creation can change ctime without changing content. This preserves strict source-change detection during acquisition. The supervisor revalidates before acquisition, every cached range publication and successful EOF; a changed source fails with retry guidance and cannot complete a checkpoint. This is trusted local filesystem generation evidence, not cryptographic source identity or proof against a filesystem/provider that lies about change metadata. Symlink retargeting changes the revision. Random-access ZIP/PDF adapters can complete a checkpoint using stable path-generation evidence without claiming full raw-byte hash coverage. Only an actual acquired-byte receipt authorizes content-identity migration.

Missing/incompatible manifests miss safely. Corrupt ranges invalidate only their immutable generation; retry rebuilds from the untouched source rather than resuming a prefix. Partial checkpoints are not complete/exportable books. Explicit repository/controller export reads every committed range in order, checks contiguous source/word/segment coverage and manifest totals, then merges derived graphs on a pure worker. Segment/cast IDs and annotation/evidence content are retained; producer-local annotation/pronunciation counter IDs are qualified by range, and global ordinals/voice word offsets are adjusted. This produces an ordinary v4 `.radoc` or complete audio-planning graph without rerunning analysis. Export metadata memory grows with the complete graph; it is not on the opening/replay path. One controller export is admitted at a time. Replacement cancels publication between reads and after finite worker work; staged files are renamed only while current, temporary files are removed on failure/cancel, and shutdown awaits document-export drain. The controller exposes the document-export API but adds no save-document UI in this slice. External assets/native resources are not made portable by graph export. Normal-app restore, timing and emitted-audio qualification remain with #83/#90.

Preparation exposes controller APIs for cancellation and retry (`cancelDocumentPreparation`, `retryDocumentPreparation`), stage progress, and bounded range consumption. Cancellation suppresses stale publication and releases a paused consumer credit; retries start a new operation revision. The normal picker path also refuses malformed `.radoc` input while preserving the active document. These APIs and tests establish software behavior only; they do not establish native app acceptance, release readiness or audible output quality.

`SpeechAnnotation` also represents optional span-level delivery intent (`whispered`, `shouted`, `spoken`, `sung`) and inflection intent (`rising`, `falling`, `level`). Each intent carries explicit-source/user provenance and confidence; unknown remains absent. The inference service accepts caller-supplied explicit intents with validated speech-word ranges; it does not infer performance or emotion from prose, punctuation or dialogue tags. Importers and UI do not yet supply these intents automatically. V2 preserves these canonical values and rejects invalid vocabulary, provenance, confidence or spans during decode; V1 omits the new kinds to preserve its existing output. Voice-session realization retains each intent and records `unsupported` with `engine_default` fallback in session/segment diagnostics for current engine adapters; this does not claim or alter acoustic delivery. See [R3 slice #79](https://github.com/kellyjanderson/readaloud/issues/79).

Residual limits are explicit: the controller constructs the small fixed bundled sample synchronously at startup; later sample requests use the worker. `loadDocument` accepts an already constructed complete graph. Headless export/probe runners still call the importer directly and do not host the interactive range/checkpoint lifecycle. An injected importer is a controllable test/legacy adapter on the caller isolate, not production-worker proof. Runtime realization and cast-aware chunk planning run in the resident planning worker, with separate playback/export owners and bounded returned windows. Framework HTML layout remains on Flutter. RC2 has bounded local implementation evidence, but current integrated native build/app behavior, launch timing, emitted-audio continuity and human listening remain unqualified; no native, release or audio acceptance is claimed. See #83 and #90 for current gates.

## Incremental whole-document display

The transport's `ReaderController.document` remains the active audio fragment;
it is not the whole displayed book. `RangeDocumentSurface` presents all published
ranges through a lazy variable-height `SuperListView`, preserving document styles
with inline `DocumentSurface` cells. The maintained list supplies native scrollbar
and index-based follow/recenter behavior; an ordinary ListView cannot reliably
recenter an unmounted variable-height range. A trailing viewport cell requests the
next range as the user scrolls, so display demand can advance preparation without
Play. EOF has an explicit end-of-document marker and cumulative word count.

`readPreparedRange` coalesces identical requests and admits at most eight reads.
It reuses resident publications or reads a committed immutable checkpoint on a
repository worker. Only an active request revision can return data. Viewport
cells cancel their waits on disposal; already admitted immutable IO may finish,
while replacement/shutdown invalidates the result and wakes waiters. The eight
resident preparation fragments remain bounded: viewport demand releases producer
credit, and playback can retrieve evicted ranges from the same checkpoint. The
publication owner signals when credit becomes available as well as when a range
arrives, avoiding a demand-before-credit lost wakeup. Lightweight list/key/index
metadata may grow with published range count; whole semantic graphs/HTML widgets
are not retained for every page. Single-snapshot/legacy imports retain their
existing surface and are not novel-scale virtualization evidence.

The R6 signed native text probe checks rendered tail text plus a visible EOF
marker, rather than treating prepared-range counts as display proof. Viscera's
six ranges/3,456 words and a 139-range/90,005-word synthetic novel reached their
actual displayed ending with no speech request. This does not qualify every
format, full-novel acoustic continuity or universal launch-to-speech timing.

## Source and tests

- [document_preparation_supervisor.dart](../../lib/src/services/document_preparation_supervisor.dart)
- [document_preparation_supervisor_test.dart](../../test/document_preparation_supervisor_test.dart)
- [document_import_service.dart](../../lib/src/services/document_import_service.dart)
- [reader_controller.dart](../../lib/src/controllers/reader_controller.dart)
- [chunk_planner_service.dart](../../lib/src/services/chunk_planner_service.dart)
- [reader_document_serialization_service.dart](../../lib/src/services/reader_document_serialization_service.dart)
- [reader_document_repository.dart](../../lib/src/services/reader_document_repository.dart)
- [file_source_revision.dart](../../lib/src/services/file_source_revision.dart)
- [reader_document_repository_test.dart](../../test/reader_document_repository_test.dart)
- [file_source_revision_test.dart](../../test/file_source_revision_test.dart)
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

## Durable linguistic evidence

`ReaderDocumentRepository.analysis` owns the incremental book's immutable analysis
records in Application Support, under `prepared-documents/analysis`. Record keys
include source revision, exact bounded normalized text, upstream/model/adapter
identity and window policy; per-session request IDs are rebound on restore and
are never persisted as reusable identity. Each record has a checksum and bounded
schema validation. `ModernBookNlpAnalysis` checks embedded/imported records and then
the working store before creating or loading a provider. A corrupt record is a miss
and is replaced only after a new valid result succeeds; file-system failures remain
actionable. Older dependency records remain exportable evidence but are not reused.

The supervisor owns one current exchange and latest pending demand, including
persistence, so there is no additional writer queue. Encoding, checksums, validation,
file I/O and restored-result decoding run in isolates. The UI owner admits an atomic
rename only while the source/session is current and checks again before publishing
completion. A replacement during the admitted rename can leave an immutable record
for the old book, never publish its result into the new book. Stop/shutdown drain the
finite save operation; they do not kill a filesystem worker mid-write. A failed or
cancelled stage is removed. Multi-process writers to the same book are not qualified.

`.radoc-v4` serializes the same evidence alongside Character selections and prepared
input; v1–v3 readers remain supported. Explicit export collects committed records for
the current source and merges embedded records, and rejects duplicate or nonmatching
window text on import. A copied artifact can restore a saved window without model
assets or a provider runtime. Whole portable decoding/export still materializes the
book graph on a worker; it is not a paged container or portable rendered audio.
S2 selects analysis windows at the playback position in imported books, including
forward/backward jumps. Both legacy newline and paragraph-context-v2 records are
validated against their corresponding source layout and retained on re-export;
different policy/text does not reuse an incompatible result. The same supervisor
awaits isolate-owned Character projection after persistence, then current-owner
admission can refine future routes through the existing Character aggregate.
See [character integration](character-dialogue-attribution-and-voice-casting.md#experimental-local-neural-provider)
for scope, precedence and evidence limits.

The book owns semantic content anchors independently of a voice rendition. Shared
continuous-period integration, explicit temporal referents, rendition alignment and
portable media/audio manifests remain proposed in [R19](https://github.com/kellyjanderson/readaloud/issues/110#issuecomment-6670899379)
and [R20](https://github.com/kellyjanderson/readaloud/issues/110#issuecomment-6671095679).
The separate C++17/C ABI interval stub has Python/Dart bindings; Read Aloud does not
yet link it. NLP offsets must never be treated as emitted-audio timestamps.

## S6 portable audio books

The normal intake route recognizes the `read-aloud-audio-book` ZIP envelope
(`radoc-v5`) before reading legacy JSON. `RadocAudioPackage` validates a bounded
manifest and archive directory on its worker, then materializes only requested
prepared ranges, analysis records and WAV members. Member hashes, sizes, names,
coverage and PCM formats are checked; unknown versions and corrupt demanded
members fail visibly. Legacy v1–v4 JSON remains readable.

A book session retains its security-scoped input lease and private materialized
files until player stop and package/boundary worker drain. The controller keeps
at most eight prepared ranges. Later ranges merge their Character evidence into
the existing WorkCharacterStore without replacing newer local selections; an
explicit republish also merges unread ranges before serializing their registry.
Analysis records remain separately loadable through the existing analysis owner.

Normal app startup defers synthesis until launch/open/restore intake is known.
Complete rendered books enter the existing player's rendered-audio capability
without model initialization, voice loading, binding preparation or inference.
A missing or invalid scene demands the existing bounded export/synthesis path,
commits its output, and returns to saved-scene resolution. Valid following scenes
are reused. Historical boundaries incompatible with prepared segments are refused
rather than expanded silently. Basic source spans remain approximate highlighting,
not advanced alignment. The S6 acceptance/evidence authority is [#137](https://github.com/kellyjanderson/readaloud/issues/137);
source implementation does not waive launch, emitted-audio or human gates.

The macOS Save Audio Book path obtains only the chosen destination through the
native Save panel. A utility-queue Foundation `itemReplacementDirectory` request
allocates private staging on the destination volume; it does not require access
to arbitrary siblings. Package cancellation/deadline ownership begins before that
request, and stale returned directories are cleaned. The existing archive worker
flushes output, obtains current-owner commit admission and renames atomically;
it never falls back to cross-device copying. Native allocation and publication
errors propagate to the controller's diagnostics and visible failure state.

When saved audio is playing, a missing scene may prepare its model bindings and
enter the existing native export owner. Rendered playback does not occupy the
synthesis lane; treating it as ordinary synthesis previously prevented this work
from starting. Ordinary synthesized playback still retains its existing resource
and low-water admission policy. The export completion metric records the actual
source span, cache-hit result and raw artifact identity for native qualification.
