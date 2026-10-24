# Pronunciation Planning and TTS Artifacts

Reconciled: October 24, 2026
Status: Current source architecture; runtime validation not refreshed

## Implemented structure and limitations

The document-time planner creates pronunciation artifacts from normalized speech, annotations, profile resources and rule modules. Realization produces voice/session-specific TTS artifacts retaining normalized segment and word-range provenance. These artifacts are passed to runtime chunk derivation and engine translation.

Canonical pronunciation intent and engine-specific payloads are separate. Unsupported or uncovered tokens can fall back to engine handling; fallback is not proof of a positive pronunciation decision. Pronunciation probe and sentence-probe tooling expose generated output and trace information.

The import planner and controller realization are synchronous service calls today. The runtime does not make all upstream policy worker-owned merely because inference uses an isolate. Moving these passes and establishing prepared-document version ownership belongs to the active ACD. Speech-quality acceptance still requires emitted-audio evidence, not only artifact structure.

## Source and tests

- [document_time_pronunciation_planner_service.dart](../../lib/src/services/document_time_pronunciation_planner_service.dart)
- [pronunciation_artifact.dart](../../lib/src/models/pronunciation_artifact.dart)
- [tts_artifact.dart](../../lib/src/models/tts_artifact.dart)
- [voice_session_realization_service.dart](../../lib/src/services/voice_session_realization_service.dart)
- [document_time_pronunciation_planner_service_test.dart](../../test/document_time_pronunciation_planner_service_test.dart)
- [voice_session_realization_service_test.dart](../../test/voice_session_realization_service_test.dart)

Tests listed here are existing evidence locations, not a claim that they passed in this review. The bundled Intel Dart executable cannot run in the current Apple Silicon execution environment.

## Proposed changes

See [prepared document runtime ACD](../acd/prepared-document-runtime.acd) and its [implementation plan](../planning/prepared-document-runtime.plan). Historical design prose is preserved in the [architecture snapshot](../archive/architecture/2026-10-24/pronunciation-planning-and-tts-artifacts.md).

## Retained child contracts

These legacy contracts describe intended behavior and acceptance; `final` denotes refinement, not verified implementation. New changes use an ACD and plan.

- [document time pronunciation planner](../specifications/document-time-pronunciation-planner.md)
- [engine pronunciation translation policy](../specifications/engine-pronunciation-translation-policy.md)
- [pronunciation artifact model](../specifications/pronunciation-artifact-model.md)
- [pronunciation diagnostics and observability](../specifications/pronunciation-diagnostics-and-observability.md)
- [pronunciation fallback and traceability](../specifications/pronunciation-fallback-and-traceability.md)
- [speech qa debug tooling](../specifications/speech-qa-debug-tooling.md)
- [tts runtime chunk request derivation](../specifications/tts-runtime-chunk-request-derivation.md)
- [voice session pronunciation realization](../specifications/voice-session-pronunciation-realization.md)
