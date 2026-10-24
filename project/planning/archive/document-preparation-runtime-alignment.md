# Document Preparation Runtime Alignment

Date: October 24, 2026
Status: Accepted architecture direction; implementation not started in this documentation change

## Decisions

The user clarified that all document semantics are prepared before playback: stable character data, supported presented-gender evidence, voice bindings, speaker tags, pronunciation, inflection and delivery intent. Character voice resources are initialized for the document and retained through ordinary speaker changes. The synthesis runtime fills an audio buffer ahead of playback; a character boundary is never a transport restart.

The [execution-context architecture](../../acd/prepared-document-runtime.acd) records these decisions and the thread-placement review. It distinguishes full-document semantic preparation from bounded waveform generation. Model choice and numerical buffer thresholds remain open pending evaluation. No neural migration is authorized by these documents alone.

## Review of Architectural Guidance

The older runtime architecture already required a long-lived worker and native background queue. It did not reliably prevent synchronous document preparation or controller-side planning. First-chunk startup and broad voice-change reset wording encouraged behavior inconsistent with the clarified design. The updated architecture assigns every producer an execution lane and requires ownership, bounded queues, cancellation, failure and stale-result contracts before implementation.

## Code Improvement Work Items

These are local planning records, not claims that external issues have been filed. Use the linked specifications as implementation anchors and preserve the distinction between implementation and running-app verification.

| Work item | Source locations and gap | Required result |
| --- | --- | --- |
| Background document preparation | `lib/src/services/document_import_service.dart`: `_buildReaderDocument`; `lib/src/controllers/reader_controller.dart`: `_setDocumentLoadStage` | Preparation supervisor owns parsing through instrumented revision publication; whole-document completion gate; responsive UI |
| Move realization and planning | `lib/src/controllers/reader_controller.dart`: `_refreshRealizationWindow`, `_refreshChunkPlan`, `_primePlaybackPreparation` | Worker-owned planning over prepared document; bounded request/result handoff |
| Resident synthesis resources | `lib/src/services/kokoro_speech_worker_processor.dart`: `process`, `_kokoroWorkerEntryPoint`; `lib/src/services/kokoro_model_runner.dart`: `runInference`, `dispose` | Persistent worker/model, loaded character voices, released per-inference tensors, supervised termination |
| Buffered revision commit | `lib/src/controllers/reader_controller.dart`: `selectVoiceById`; `lib/src/services/kokoro_tts_engine.dart`: runtime/queue coordination | Normal character changes append without restart; assignment edits commit prepared future audio; newest startup selection wins |
| Stale document rejection | `lib/src/controllers/reader_controller.dart`: `_reloadLiveReadFile`, `_replaceDocument` | Serialized/coalesced imports; reject stale success/failure/cancellation before document or loading-state mutation |
| Binding and cache provenance | `lib/src/models/character_cast_registry.dart`; `lib/src/models/cast_voice_assignment.dart`; `lib/src/services/kokoro_assets.dart`; `lib/src/services/kokoro_speech_worker_processor.dart`: cache validation | Character-owned binding references and model/voice fingerprints; atomic publication; no stale audio reuse |

## Delivery Order

1. Establish a runnable native toolchain and baseline tests/audio measurements.
2. Implement document preparation messages, immutable revisions and readiness gates.
3. Align character bindings and resident runtime resource ownership, including cleanup and failure handling.
4. Move realization/planning off the UI and implement measured audio-lead scheduling.
5. Implement assignment revision commits and source-reload stale-result rejection.
6. Validate responsiveness, continuous audio and bounded resource usage through the actual app; evaluate attribution providers separately on labeled passages.

## Verification and Open Choices

[Prepared Document and Buffered Playback](../../test-specifications/prepared-document-and-buffered-playback.md) defines required integrated scenarios. No code or audio tests were run for this documentation change. Buffer targets must be selected from supported-device measurements; backend support for safe future-queue replacement must be demonstrated before promising immediate assignment application. Character analysis quality remains an evaluation task even when all analysis happens ahead of playback.
