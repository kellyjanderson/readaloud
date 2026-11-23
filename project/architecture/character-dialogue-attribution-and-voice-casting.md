# Character Dialogue Attribution and Voice Casting

Reconciled: November 4, 2026; directed progressive-discovery/Fish slice; release integration pending
Status: Fast discovery, bounded heuristic refinement and Fish reference binding implemented; full Character migration and native chapter acceptance pending

## Implemented structure and limitations

Import detects dialogue and applies an ordered heuristic attribution provider. It tries explicit local tags, adjacent tags, paragraph ownership, alternation, pronoun resolution and persistence. Its numeric confidence values are fixed rule scores, not calibrated probabilities; unattributed outcomes are explicit.

The incremental importer publishes provisional characters recognized from explicit narrative speaker tags before resolving dialogue. It reuses the existing tag recognizer, identity evidence and cast IDs. A subsequent pass resolves dialogue, aliases and routes with a bounded twelve-segment halo on each side. Preceding dialogue annotations travel with that halo; analysis-only paragraph indices are rebased by stable block identity so range-local indices cannot attach the next quote to an earlier speaker. Published source spans/IDs remain unchanged. Discovery does not require whole-document preparation or write an automatic choice as user intent.

`CharacterDiscoveryPublication` is an optional notification from the existing preparation isolate. The supervisor owns its owner/source/watch/revision identity, accepts at most one discovery for the next range sequence, and rejects obsolete success. The existing one-outstanding-range credit bounds admission; cancellation retires the worker and rejects later refinement. The controller merges sparse evidence upserts into its existing session registry. No second worker queue, cast store or model owner was introduced. This is two observable passes within one bounded worker, not an independently scheduled neural provider. ModernBookNLP and the common CharacterAnalysisDelta/persistent Character migration remain open in [#125](https://github.com/kellyjanderson/readaloud/issues/125), [#126](https://github.com/kellyjanderson/readaloud/issues/126) and [#127](https://github.com/kellyjanderson/readaloud/issues/127).

The cast registry canonicalizes aliases and includes a narrator. The current character model already has identity labels, evidence source/spans, pronoun counts and conflict information. The service examines explicit identity/apposition, descriptors and pronoun evidence after clustering. Earlier claims that only a narrow gender field existed were stale; the actual extraction remains rule-based and its accuracy is not established by this review.

The controller exposes a session-wide `characterCastRegistry` from revision-gated accumulated discoveries and alias redirects. Voice Management and its assignment resolution use this registry rather than the currently displayed fragment, which could omit later speakers. New playback/export planning contexts overlay admitted session evidence on their range registry and retain captured explicit voice intent. Already active contexts remain immutable; newly discovered evidence is used by future contexts. Document replacement resets discoveries; explicit choices retain their existing persistence and precedence. The dialog reports partial discovery rather than presenting a bounded preparation window as a complete cast. [Issue #120](https://github.com/kellyjanderson/readaloud/issues/120) records the regression and verification limits; the intake widget test imports a multi-range passage and checks four speakers, a later speaker's selected voice and reset on replacement.

Assignments remain a separate `CastVoiceAssignmentSet`. Resolution prioritizes user override, stored document choice, automatic choice and fallback. Automatic casting preserves the registry’s first-encounter character order so later discoveries do not alphabetically displace earlier allocations. It first matches available gender evidence, then engine-owned preference, metadata quality and locale, avoiding reused voices where possible. Drama prefers its Fish Official references within the compatible pool; a US-English locale bonus cannot displace that engine preference or matching gender. An available matching narrator voice is preferable to an incompatible character voice. Explicit/stored choices keep precedence. Temporal tag prefixes such as “Later Mara asked” retain the character Mara rather than creating a new identity. His/Her/Their can contribute local pronoun evidence; weekdays do not masquerade as competing proper names. Uncertain/conflicting evidence remains distinct from a manual selection. Document voice attribution maps segments to cast ids; cast-aware routing maps them to effective voices. Unattributed dialogue uses narrator fallback.

Every explicit voice selection is saved, including a selection equal to the current automatic result; only Reset removes the choice. The source preference owner is stable across unfinished-book reopenings independently of temporary graph IDs. When the source obtains its canonical document identity, its saved preference snapshot takes precedence over older canonical choices, including absent roles after Reset. This transition changes future preference resolution, not already captured playback intent. See [reader session state](reader-interface-and-session-state.md) for persistence ownership and restart evidence limits.

`ResolvedPreparedVoiceReference` joins cast identity and assignment decision provenance to immutable `PreparedVoiceBinding` records. The resident worker validates model/voice content digests and request-bound fingerprints/revisions; native handles remain worker-owned. `VoiceAssignmentCoordinator` separately retains requested and effective default/cast snapshots. Edits during active playback change requested intent without changing the current chunk. Initial buffering coalesces to the newest request; effective state updates only on the current engine acknowledgment. Explicit Apply replays from the current audible source chunk start, and paused pending edits use the retained chunk-start anchor on next Play; repetition is disclosed instead of promising seamless tail replacement. Failures retain pending intent for retry. Ordinary attribution/routing never becomes a user edit. Whole-document processing does not eliminate wrong attribution; a neural provider still requires evaluation.

## Bounded native evidence

The November 4 directed slice ran the real macOS app with the local bf16 Drama checkpoint and City. A four-minute cache-assisted run completed its smoke contract: 44.1 kHz, non-silent PCM, 25 completed chunks through word 608 plus a partial next chunk, and unchanged automatic female bindings for Mara/Freya and Mira/Hannah after Mother Superior/Laura was discovered. Voice Management opened/closed during playback; the automated harness shut down its app and inference child, and process absence was verified. These are routing/PCM/UI observations, not a human judgment of perceived gender or expression.

Acceptance remains incomplete: that run took 12.605 seconds from the harness's in-app timer to 515 ms of playback (not an external launch-to-first-audio measurement). Its longest observed player-position stall was 672 ms; an earlier cold run stalled for 7.158 seconds. Existing generated audio assisted the later run, so it does not establish fresh-inference continuity. Numerous untagged City exchanges still fall back to narration or incorrect heuristic ownership; the chapter ending, full attribution quality, native normal-Quit and M3 qualification remain open. Source tests and this bounded run do not close #124/#111/#113.

## Expressiveness boundary


Existing speech annotations, delivery intent and pronunciation planning remain separate from model-specific realization. Character evidence and user voice intent are not inferred from a Fish speaker slot. Slots are runtime-local references derived from the selected catalog voices; the native adapter preserves the existing speech text/directions while adding the selected speaker tag. This prepares the binding boundary for later expressive realization without inventing another conditioning cache or claiming that typed character speech profiles are already implemented.

## Source and tests


- [speaker_attribution_service.dart](../../lib/src/services/speaker_attribution_service.dart)
- [character_cast_registry_service.dart](../../lib/src/services/character_cast_registry_service.dart)
- [character_cast_registry.dart](../../lib/src/models/character_cast_registry.dart)
- [cast_voice_assignment_service.dart](../../lib/src/services/cast_voice_assignment_service.dart)
- [document_voice_attribution_service.dart](../../lib/src/services/document_voice_attribution_service.dart)
- [cast_aware_speech_route_service.dart](../../lib/src/services/cast_aware_speech_route_service.dart)
- [progressive_character_casting_test.dart](../../test/progressive_character_casting_test.dart) covers early/refined ordering, Fish-compatible automatic choices, explicit override, range continuity, reopen and cancellation.
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
