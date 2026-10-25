# Pronunciation Planning and TTS Artifacts

Reconciled: October 24, 2026
Status: Current source architecture; runtime validation not refreshed

## Implemented structure and limitations

The document-time planner creates pronunciation artifacts from normalized speech, annotations, profile resources and rule modules. Realization produces voice/session-specific TTS artifacts retaining normalized segment and word-range provenance. These artifacts are passed to runtime chunk derivation and engine translation.

Canonical pronunciation intent and engine-specific payloads are separate. Unsupported or uncovered tokens can fall back to engine handling; fallback is not proof of a positive pronunciation decision. Pronunciation probe and sentence-probe tooling expose generated output and trace information.

Document preparation owns import-time planning in its pure Dart worker. A resident SpeechPlanningSupervisor now owns runtime realization and chunk planning; the immutable graph and routing indexes cross once per context epoch, followed by bounded scalar window requests. Playback and export retain separate planning/tokenization owners. KokoroTokenizationWorker preserves dictionary and capability identity as well as tokenizer state, avoiding isolate-local singleton drift. Its asset bridge carries raw strings; lexicon JSON, CMU dictionary conversion and G2P setup run in the pure worker, including the first fallback path. Remote initializer/request errors retain their worker stacks. Speech-quality acceptance still requires emitted-audio evidence, not only artifact structure.

## Source and tests

- [document_time_pronunciation_planner_service.dart](../../lib/src/services/document_time_pronunciation_planner_service.dart)
- [pronunciation_artifact.dart](../../lib/src/models/pronunciation_artifact.dart)
- [tts_artifact.dart](../../lib/src/models/tts_artifact.dart)
- [voice_session_realization_service.dart](../../lib/src/services/voice_session_realization_service.dart)
- [document_time_pronunciation_planner_service_test.dart](../../test/document_time_pronunciation_planner_service_test.dart)
- [voice_session_realization_service_test.dart](../../test/voice_session_realization_service_test.dart)

The pinned arm64 SDK runs resident-planner and tokenization worker regressions, including exact dictionary/IPA/suffix equivalence and cancellation/exit ownership. Native timing and perceptual pronunciation remain separate evidence.

## Proposed changes

See [prepared document runtime ACD](https://github.com/kellyjanderson/readaloud/issues/48) and its [implementation plan](https://github.com/kellyjanderson/readaloud/issues/48). Historical design prose is preserved in the [architecture snapshot](../archive/architecture/2026-10-24/pronunciation-planning-and-tts-artifacts.md).

## Retained child contracts

These legacy contracts describe intended behavior and acceptance; `final` denotes refinement, not verified implementation. New changes use GitHub design and slice issues; final architecture stays in this repository.

- [document time pronunciation planner](../specifications/document-time-pronunciation-planner.md)
- [engine pronunciation translation policy](../specifications/engine-pronunciation-translation-policy.md)
- [pronunciation artifact model](../specifications/pronunciation-artifact-model.md)
- [pronunciation diagnostics and observability](../specifications/pronunciation-diagnostics-and-observability.md)
- [pronunciation fallback and traceability](../specifications/pronunciation-fallback-and-traceability.md)
- [speech qa debug tooling](../specifications/speech-qa-debug-tooling.md)
- [tts runtime chunk request derivation](../specifications/tts-runtime-chunk-request-derivation.md)
- [voice session pronunciation realization](../specifications/voice-session-pronunciation-realization.md)
