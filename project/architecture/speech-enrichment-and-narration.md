# Speech Enrichment and Narration

Reconciled: October 25, 2026; P4 production lineage 295677e
Status: Current worker-owned source; native P4/FINAL acceptance pending

## Implemented structure and limitations

Base annotation inference attaches speech-side hints to normalized segments. The model covers boundaries, pause/emphasis candidates, discourse, pronunciation, say-as and dialogue. Annotations preserve provenance and ranges; source text remains separate from derived intent.

`NarrationState` carries session continuity and local realization choices. A resident `SpeechPlanningSupervisor` worker owns `VoiceSessionRealizationService` and cast-aware chunk planning. It retains a frozen document/routing context and accepts bounded scalar window requests. Realization expands to cover all segments in each returned chunk window, combining annotations, pronunciation resources and profile selection into TTS artifacts. The main isolate accepts identity-checked results and updates UI/control state; it does not perform this runtime realization synchronously.

Speaker attribution and character casting are implemented upstream during import; earlier architecture saying they were absent was stale. Rich delivery intent in a data model does not guarantee audible engine support. Current emphasis/prosody remains constrained by the adapter and Kokoro capabilities. Whole-document semantic preparation and worker-owned render-ahead realization are implemented. Data coverage does not establish correct attribution or audible delivery; provider selection and acoustic evaluation remain separate.

## Source and tests

- [base_speech_annotation_inference_service.dart](../../lib/src/services/base_speech_annotation_inference_service.dart)
- [speech_annotation.dart](../../lib/src/models/speech_annotation.dart)
- [narration_state.dart](../../lib/src/models/narration_state.dart)
- [voice_session_realization_service.dart](../../lib/src/services/voice_session_realization_service.dart)
- [base_speech_annotation_inference_service_test.dart](../../test/base_speech_annotation_inference_service_test.dart)
- [voice_session_realization_service_test.dart](../../test/voice_session_realization_service_test.dart)

Tests listed here are evidence locations, not a claim that every case was rerun for this page. The pinned native arm64 Flutter 3.41.5 / Dart 3.11.3 toolchain is runnable; the earlier Intel SDK failure is historical. See the [evidence index](README.md#evidence-and-acceptance-limits) for bounded source/native results.

## Design and remaining acceptance

See [prepared document runtime ACD](https://github.com/kellyjanderson/readaloud/issues/48) and its [implementation plan](https://github.com/kellyjanderson/readaloud/issues/48). Historical design prose is preserved in the [architecture snapshot](../archive/architecture/2026-10-24/speech-enrichment-and-narration.md).

## Retained child contracts

These legacy contracts describe intended behavior and acceptance; `final` denotes refinement, not verified implementation. New changes use GitHub design and slice issues; final architecture stays in this repository.

- [adjacent speaker context attribution](../specifications/adjacent-speaker-context-attribution.md)
- [append only forward playback queue](../specifications/append-only-forward-playback-queue.md)
- [automatic voice casting and override resolution](../specifications/automatic-voice-casting-and-override-resolution.md)
- [boundary candidate metadata contract](../specifications/boundary-candidate-metadata-contract.md)
- [boundary corrected chunk output and reuse](../specifications/boundary-corrected-chunk-output-and-reuse.md)
- [boundary intent realization](../specifications/boundary-intent-realization.md)
- [boundary silence thresholds](../specifications/boundary-silence-thresholds.md)
- [buffered lead time and underrun policy](../specifications/buffered-lead-time-and-underrun-policy.md)
- [cast voice override workflow](../specifications/cast-voice-override-workflow.md)
- [character cast registry model](../specifications/character-cast-registry-model.md)
- [character identity conflict resolution](../specifications/character-identity-conflict-resolution.md)
- [character identity descriptor attachment](../specifications/character-identity-descriptor-attachment.md)
- [character identity extraction pass ordering](../specifications/character-identity-extraction-pass-ordering.md)
- [character identity output schema](../specifications/character-identity-output-schema.md)
- [character pronoun profile extraction](../specifications/character-pronoun-profile-extraction.md)
- [character reference consolidation and alias clustering](../specifications/character-reference-consolidation-and-alias-clustering.md)
- [chunk planning](../specifications/chunk-planning.md)
- [context aware automatic voice casting](../specifications/context-aware-automatic-voice-casting.md)
- [dialogue span detection](../specifications/dialogue-span-detection.md)
- [discourse role annotation model](../specifications/discourse-role-annotation-model.md)
- [document replacement playback reset and stale event rejection](../specifications/document-replacement-playback-reset-and-stale-event-rejection.md)
- [document specific cast voice assignment memory](../specifications/document-specific-cast-voice-assignment-memory.md)
- [document time pronunciation planner](../specifications/document-time-pronunciation-planner.md)
- [emphasis candidate model](../specifications/emphasis-candidate-model.md)
- [emphasis intent realization](../specifications/emphasis-intent-realization.md)
- [engine intent translation policy](../specifications/engine-intent-translation-policy.md)
- [engine pronunciation translation policy](../specifications/engine-pronunciation-translation-policy.md)
- [explicit character identity evidence](../specifications/explicit-character-identity-evidence.md)
- [explicit speaker tag attribution](../specifications/explicit-speaker-tag-attribution.md)
- [file backed document restore and directory continuity](../specifications/file-backed-document-restore-and-directory-continuity.md)
- [first chunk startup contract](../specifications/first-chunk-startup-contract.md)
- [generated audio cache](../specifications/generated-audio-cache.md)
- [imported playback responsiveness policy](../specifications/imported-playback-responsiveness-policy.md)
- [initial and resumed boundary handling](../specifications/initial-and-resumed-boundary-handling.md)
- [narration state](../specifications/narration-state.md)
- [paragraph ownership and dialogue alternation](../specifications/paragraph-ownership-and-dialogue-alternation.md)
- [pause and break taxonomy](../specifications/pause-and-break-taxonomy.md)
- [playback coordination](../specifications/playback-coordination.md)
- [playback progress and jump mapping](../specifications/playback-progress-and-jump-mapping.md)
- [playback quality instrumentation](../specifications/playback-quality-instrumentation.md)
- [pronunciation artifact model](../specifications/pronunciation-artifact-model.md)
- [pronunciation candidate model](../specifications/pronunciation-candidate-model.md)
- [pronunciation diagnostics and observability](../specifications/pronunciation-diagnostics-and-observability.md)
- [pronunciation fallback and traceability](../specifications/pronunciation-fallback-and-traceability.md)
- [pronunciation realization precedence](../specifications/pronunciation-realization-precedence.md)
- [realization window policy](../specifications/realization-window-policy.md)
- [remembered reading position and startup resume](../specifications/remembered-reading-position-and-startup-resume.md)
- [running app uninterrupted speech under follow along load](../specifications/running-app-uninterrupted-speech-under-follow-along-load.md)
- [say as candidate model](../specifications/say-as-candidate-model.md)
- [speaker attribution outcome schema](../specifications/speaker-attribution-outcome-schema.md)
- [speaker attribution priority and unknown handling](../specifications/speaker-attribution-priority-and-unknown-handling.md)
- [speaker pronoun resolution and persistence](../specifications/speaker-pronoun-resolution-and-persistence.md)
- [speech annotation envelope model](../specifications/speech-annotation-envelope-model.md)
- [speech document](../specifications/speech-document.md)
- [speech worker pipeline](../specifications/speech-worker-pipeline.md)
- [trim and cap join correction](../specifications/trim-and-cap-join-correction.md)
- [tts runtime chunk request derivation](../specifications/tts-runtime-chunk-request-derivation.md)
- [uninterrupted audio primary channel](../specifications/uninterrupted-audio-primary-channel.md)
- [us english starter voice set and auto cast preference](../specifications/us-english-starter-voice-set-and-auto-cast-preference.md)
- [voice session pronunciation realization](../specifications/voice-session-pronunciation-realization.md)
- [voice session realization envelope](../specifications/voice-session-realization-envelope.md)
- [watched file session refresh](../specifications/watched-file-session-refresh.md)
