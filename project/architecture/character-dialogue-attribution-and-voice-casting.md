# Character Dialogue Attribution and Voice Casting

Reconciled: October 25, 2026; P4 production lineage 295677e
Status: Implemented casting/resource references and P4 assignment source; native assignment acceptance pending

## Implemented structure and limitations

Import detects dialogue and applies an ordered heuristic attribution provider. It tries explicit local tags, adjacent tags, paragraph ownership, alternation, pronoun resolution and persistence. Its numeric confidence values are fixed rule scores, not calibrated probabilities; unattributed outcomes are explicit.

The cast registry canonicalizes aliases and includes a narrator. The current character model already has identity labels, evidence source/spans, pronoun counts and conflict information. The service examines explicit identity/apposition, descriptors and pronoun evidence after clustering. Earlier claims that only a narrow gender field existed were stale; the actual extraction remains rule-based and its accuracy is not established by this review.

Assignments remain a separate `CastVoiceAssignmentSet`. Resolution prioritizes user override, stored document choice, automatic choice and fallback. Automatic casting scores voice metadata and avoids narrator/reused voices where possible. Document voice attribution maps segments to cast ids; cast-aware routing maps them to effective voices. Unattributed dialogue uses narrator fallback.

`ResolvedPreparedVoiceReference` joins cast identity and assignment decision provenance to immutable `PreparedVoiceBinding` records. The resident worker validates model/voice content digests and request-bound fingerprints/revisions; native handles remain worker-owned. `VoiceAssignmentCoordinator` separately retains requested and effective default/cast snapshots. Edits during active playback change requested intent without changing the current chunk. Initial buffering coalesces to the newest request; effective state updates only on the current engine acknowledgment. Explicit Apply replays from the current audible source chunk start, and paused pending edits use the retained chunk-start anchor on next Play; repetition is disclosed instead of promising seamless tail replacement. Failures retain pending intent for retry. Ordinary attribution/routing never becomes a user edit. Whole-document processing does not eliminate wrong attribution; a neural provider still requires evaluation.

## Source and tests

- [speaker_attribution_service.dart](../../lib/src/services/speaker_attribution_service.dart)
- [character_cast_registry_service.dart](../../lib/src/services/character_cast_registry_service.dart)
- [character_cast_registry.dart](../../lib/src/models/character_cast_registry.dart)
- [cast_voice_assignment_service.dart](../../lib/src/services/cast_voice_assignment_service.dart)
- [document_voice_attribution_service.dart](../../lib/src/services/document_voice_attribution_service.dart)
- [cast_aware_speech_route_service.dart](../../lib/src/services/cast_aware_speech_route_service.dart)
- [speaker_attribution_service_test.dart](../../test/speaker_attribution_service_test.dart)
- [character_cast_registry_service_test.dart](../../test/character_cast_registry_service_test.dart)
- [cast_voice_assignment_service_test.dart](../../test/cast_voice_assignment_service_test.dart)
- [document_voice_attribution_service_test.dart](../../test/document_voice_attribution_service_test.dart)

Tests listed here are evidence locations, not a claim that every case was rerun for this page. The pinned native arm64 Flutter 3.41.5 / Dart 3.11.3 toolchain is runnable; the earlier Intel SDK failure is historical. See the [evidence index](README.md#evidence-and-acceptance-limits) for bounded source/native results.

## Design and remaining acceptance

See [prepared document runtime ACD](https://github.com/kellyjanderson/readaloud/issues/48) and its [implementation plan](https://github.com/kellyjanderson/readaloud/issues/48). Historical design prose is preserved in the [architecture snapshot](../archive/architecture/2026-10-24/character-dialogue-attribution-and-voice-casting.md).

## Retained child contracts

These legacy contracts describe intended behavior and acceptance; `final` denotes refinement, not verified implementation. New changes use GitHub design and slice issues; final architecture stays in this repository.

- [adjacent speaker context attribution](../specifications/adjacent-speaker-context-attribution.md)
- [automatic voice casting and override resolution](../specifications/automatic-voice-casting-and-override-resolution.md)
- [cast aware speech range routing](../specifications/cast-aware-speech-range-routing.md)
- [cast voice override workflow](../specifications/cast-voice-override-workflow.md)
- [character cast registry model](../specifications/character-cast-registry-model.md)
- [character identity conflict resolution](../specifications/character-identity-conflict-resolution.md)
- [character identity descriptor attachment](../specifications/character-identity-descriptor-attachment.md)
- [character identity extraction pass ordering](../specifications/character-identity-extraction-pass-ordering.md)
- [character identity output schema](../specifications/character-identity-output-schema.md)
- [character pronoun profile extraction](../specifications/character-pronoun-profile-extraction.md)
- [character reference consolidation and alias clustering](../specifications/character-reference-consolidation-and-alias-clustering.md)
- [context aware automatic voice casting](../specifications/context-aware-automatic-voice-casting.md)
- [dialogue span detection](../specifications/dialogue-span-detection.md)
- [document load voice attribution materialization](../specifications/document-load-voice-attribution-materialization.md)
- [document specific cast voice assignment memory](../specifications/document-specific-cast-voice-assignment-memory.md)
- [explicit character identity evidence](../specifications/explicit-character-identity-evidence.md)
- [explicit speaker tag attribution](../specifications/explicit-speaker-tag-attribution.md)
- [paragraph ownership and dialogue alternation](../specifications/paragraph-ownership-and-dialogue-alternation.md)
- [quoted dialogue voice segmentation](../specifications/quoted-dialogue-voice-segmentation.md)
- [running app multi voice playback switching](../specifications/running-app-multi-voice-playback-switching.md)
- [speaker attribution outcome schema](../specifications/speaker-attribution-outcome-schema.md)
- [speaker attribution priority and unknown handling](../specifications/speaker-attribution-priority-and-unknown-handling.md)
- [speaker pronoun resolution and persistence](../specifications/speaker-pronoun-resolution-and-persistence.md)
- [us english starter voice set and auto cast preference](../specifications/us-english-starter-voice-set-and-auto-cast-preference.md)
- [voice metadata model and source normalization](../specifications/voice-metadata-model-and-source-normalization.md)
- [voice routed progress and diagnostics](../specifications/voice-routed-progress-and-diagnostics.md)
