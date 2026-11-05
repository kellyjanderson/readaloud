# Character Dialogue Attribution and Voice Casting

Reconciled: November 5, 2026; directed Character ownership slice; release integration pending
Status: Persistent Character/selection owner and additive migration implemented; provider quality, full Character contract and native chapter acceptance pending

## Implemented structure and limitations

Import detects dialogue and applies an ordered heuristic attribution provider. It tries explicit local tags, adjacent tags, paragraph ownership, alternation, pronoun resolution and persistence. Its numeric confidence values are fixed rule scores, not calibrated probabilities; unattributed outcomes are explicit.

The incremental importer publishes provisional characters recognized from explicit narrative speaker tags before resolving dialogue. It reuses the existing tag recognizer, identity evidence and cast IDs. A subsequent pass resolves dialogue, aliases and routes with a bounded twelve-segment halo on each side. Preceding dialogue annotations travel with that halo; analysis-only paragraph indices are rebased by stable block identity so range-local indices cannot attach the next quote to an earlier speaker. Published source spans/IDs remain unchanged. Discovery does not require whole-document preparation or write an automatic choice as user intent.

`CharacterDiscoveryPublication` is an optional notification from the existing preparation isolate. The supervisor owns its owner/source/watch/revision identity, accepts at most one discovery for the next range sequence, and rejects obsolete success. The existing one-outstanding-range credit bounds admission; cancellation retires the worker and rejects later refinement. The controller admits sparse evidence through `CharacterAnalysisDelta` into `WorkCharacterStore`, then projects the current work into its session registry. There is no second worker queue or model owner. This is two observable passes within one bounded worker, not an independently scheduled neural provider. Provider-neutral reconciliation, ModernBookNLP and full-contract acceptance remain open in [#125](https://github.com/kellyjanderson/readaloud/issues/125), [#126](https://github.com/kellyjanderson/readaloud/issues/126) and [#127](https://github.com/kellyjanderson/readaloud/issues/127).

The cast registry canonicalizes aliases and includes a narrator. The current character model already has identity labels, evidence source/spans, pronoun counts and conflict information. The service examines explicit identity/apposition, descriptors and pronoun evidence after clustering. Earlier claims that only a narrow gender field existed were stale; the actual extraction remains rule-based and its accuracy is not established by this review.

The controller exposes a session-wide `characterCastRegistry` from revision-gated accumulated discoveries and alias redirects. Voice Management and its assignment resolution use this registry rather than the currently displayed fragment, which could omit later speakers. New playback/export planning contexts overlay admitted session evidence on their range registry and retain captured explicit voice intent. Already active contexts remain immutable; newly discovered evidence is used by future contexts. Document replacement changes the visible work projection and cancels its analysis admission; reopening a known work retains its aggregate and selections. The dialog reports partial discovery rather than presenting a bounded preparation window as a complete cast. [Issue #120](https://github.com/kellyjanderson/readaloud/issues/120) records the regression and verification limits; the intake widget test imports a multi-range passage and checks four speakers, a later speaker's selected voice and reset on replacement.

Assignments remain a separate `CastVoiceAssignmentSet`. Resolution prioritizes user override, stored document choice, automatic choice and fallback. The owner retains compatible automatic resolutions per engine and reserves those voices before allocating newly discovered characters. Catalog reordering and partial publications cannot shift an existing compatible assignment. Stronger gender evidence may change an automatic resolution; an explicit selection cannot be changed by analysis. It first matches available gender evidence, then engine-owned preference, metadata quality and locale, avoiding reused voices where possible. Drama prefers its Fish Official references within the compatible pool; a US-English locale bonus cannot displace that engine preference or matching gender. An available matching narrator voice is preferable to an incompatible character voice. Explicit/stored choices keep precedence. Temporal tag prefixes such as “Later Mara asked” retain the character Mara rather than creating a new identity. His/Her/Their can contribute local pronoun evidence; weekdays do not masquerade as competing proper names. Uncertain/conflicting evidence remains distinct from a manual selection. Document voice attribution maps segments to cast ids; cast-aware routing maps them to effective voices. Unattributed dialogue uses narrator fallback.

Every explicit voice selection is saved, including a selection equal to the current automatic result. Reset writes a versioned automatic-mode tombstone; an absent choice and a Reset are distinct. The source preference owner is stable across unfinished-book reopenings independently of temporary graph IDs. When the source obtains its canonical document identity, its saved preference snapshot takes precedence over older canonical choices, including absent roles after Reset. This transition changes future preference resolution, not already captured playback intent. See [reader session state](reader-interface-and-session-state.md) for persistence ownership and restart evidence limits.

`ResolvedPreparedVoiceReference` joins cast identity and assignment decision provenance to immutable `PreparedVoiceBinding` records. The resident worker validates model/voice content digests and request-bound fingerprints/revisions; native handles remain worker-owned. `VoiceAssignmentCoordinator` separately retains requested and effective default/cast snapshots. Edits during active playback immediately schedule the latest requested intent through the existing playback-start driver. Initial buffering coalesces to the newest request; effective state updates only on the current engine acknowledgment. Automatic replacement replays from the current audible source chunk start, and paused pending edits use the retained chunk-start anchor on next Play; repetition is disclosed instead of promising seamless tail replacement. Failures retain pending intent for retry. Ordinary attribution/routing never becomes a user edit. Whole-document processing does not eliminate wrong attribution; a neural provider still requires evaluation.

## Character owner and persistence

`CastEntry implements Character`; it embeds `CharacterState` rather than shadowing
another independently writable character database. The public view exposes work
identity, revision, aliases, separate explicit/implicit/scoped presented gender,
existing typed identity attributes, selected voice and speech-profile references.
These fields are immutable. No native tensor, speaker slot or model-specific
instruction is serialized. Presented evidence can be admitted/restored; the current
heuristic does not yet extract presentation or comprehensive relationships.

`WorkCharacterStore` is the main-isolate writer. Preparation runs in the existing
worker/supervisor, whose owner/source/watch gates precede the store's
work/source/analysis-revision/provider-sequence checks. Cancellation revokes
admission; duplicate/obsolete success cannot mutate a successor. Provider deltas
cannot import a voice choice. Only explicit selection, legacy migration or explicit
`.radoc` restore can seed selection intent. Work aliases join provisional/canonical
IDs without independently writable copies. Character redirects carry choices and
prevent old-ID publications recreating duplicates. Conflicting explicit choices
retain both records and a conflict instead of silently merging them; a dedicated
merge/split correction UI is not implemented. Sparse weaker profiles cannot erase
stronger existing gender evidence. Original evidence categories remain separate.

The controller's stored-choice map, edit map, casting registry and planning maps
are projections. `VoiceAssignmentCoordinator` still owns captured requested versus
audible revisions; automatic analysis does not become a manual edit. A voice
unavailable in another engine falls back for realization while retaining its
original selection. Returning to the compatible engine restores that intent.

The existing one-active/one-pending preference pump saves a versioned immutable
character snapshot, `reader.workCharacters.v1`. Snapshot capture copies record
references; recursive JSON conversion/validation runs in `Isolate.run`. A successful
new write retires the legacy voice-map key. Future/corrupt schemas fail visibly and
block default overwrites. `.radoc` v3 uses the same character codec and the existing
atomic export writer; v1/v2 remain readable. Explicit export overlays the owner's
captured registry, including Reset, on the prepared graph. Existing local intent
wins over stale imported intent. Native assets remain external.

**Limits:** this is the first ownership migration, not the entire R2 contract.
Preferences currently load/save the retained work collection as one snapshot;
there is no paged evidence repository or crash-durable character journal. Existing
compact provider profiles do not recover evidence discarded before this slice.
Provider-native entity reconciliation, split corrections, calibrated confidence,
full attribute history and richer exact-model binding specs remain with
[#126](https://github.com/kellyjanderson/readaloud/issues/126),
[#125](https://github.com/kellyjanderson/readaloud/issues/125) and
[#127](https://github.com/kellyjanderson/readaloud/issues/127).
The user's earlier Rosalina report (inflated cast, unstable voices and poor
attribution) remains recorded. The user subsequently reported much improved
attribution with the second slice; this is useful product feedback, not a labeled
corpus score or completion of the remaining attribution acceptance.

## Expandable voice-selection contract

Named VS cases live in [the owner contract](../../test/character_voice_selection_contract_test.dart),
[serialization tests](../../test/reader_document_serialization_service_test.dart),
and [preference migration tests](../../test/reader_preferences_service_test.dart).
They cover reordering/growing/partial cast, explicit-equals-auto, conflicting
inference, Reset, reopen, stale/cancelled publications, work isolation, aliases,
conflicting merges, separate gender facts, immutable snapshots, unavailable voices
and engine A/B/A. Existing [controller assignment tests](../../test/reader_voice_assignment_revision_test.dart)
retain requested/effective and stale native-ack coverage. The
[native smoke](../../tools/mlx_playback_smoke.dart) optionally follows a named
character's alternate voice through source reopen, prepared references and played
turns (`READALOUD_SMOKE_CHARACTER`). Each future provider must reuse these cases
and add independent prose/attribution oracles; passing voice-ID tests is not proof
of correct dialogue ownership or perceived speaker identity.

## Bounded native evidence

The November 4 directed slice ran the real macOS app with the local bf16 Drama checkpoint and City. A four-minute cache-assisted run completed its smoke contract: 44.1 kHz, non-silent PCM, 25 completed chunks through word 608 plus a partial next chunk, and unchanged automatic female bindings for Mara/Freya and Mira/Hannah after Mother Superior/Laura was discovered. Voice Management opened/closed during playback; the automated harness shut down its app and inference child, and process absence was verified. These are routing/PCM/UI observations, not a human judgment of perceived gender or expression.

Acceptance remains incomplete: that run took 12.605 seconds from the harness's in-app timer to 515 ms of playback (not an external launch-to-first-audio measurement). Its longest observed player-position stall was 672 ms; an earlier cold run stalled for 7.158 seconds. Existing generated audio assisted the later run, so it does not establish fresh-inference continuity. Numerous untagged City exchanges still fall back to narration or incorrect heuristic ownership; the chapter ending, full attribution quality, native normal-Quit and M3 qualification remain open. Source tests and this bounded run do not close #124/#111/#113.

The November 5 ownership probe ([receipt and limits](https://github.com/kellyjanderson/readaloud/issues/126#issuecomment-6655612725)) verified an explicit Mara/Sophia choice through source reopen, content-addressed native binding and one completed 1.3-second character turn in a 110-word City dialogue excerpt. Output was non-silent 44.1 kHz PCM. Gender evidence in that excerpt remained unknown; the test did not infer identity from the selected voice. **Overall smoke failed** with a 4404 ms observed stall; the in-app first-playback timer was 16.351 seconds. A prior full-source run took 111.325 seconds and did not reach Mara in its three-minute window. These timers include probe setup/reopen and do not replace the required external launch benchmark. All five owned sessions received normal Quit and verified process exit. Native UI interaction, perceptual listening, full chapter and M3 acceptance remain unproved. The 681-test/2-skip source pass and the positive selection subcase do not erase those failures.

## Expressiveness boundary


Existing speech annotations, delivery intent and pronunciation planning remain separate from model-specific realization. Character evidence and user voice intent are not inferred from a Fish speaker slot. Slots are runtime-local references derived from the selected catalog voices; the native adapter preserves the existing speech text/directions while adding the selected speaker tag. This prepares the binding boundary for later expressive realization without inventing another conditioning cache. `CharacterSpeechProfile` now retains canonical direction references; expressive generation and exact-model adjustment realization remain separate work.

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

### Shared analysis admission

`CharacterAnalysisAdapter` adapts fast discovery and refined prepared fragments
into `CharacterAnalysisDelta`. Refinement retains provider/version/model identity
and maps each source-scoped dialogue segment/word span to its canonical cast ID,
including multi-segment dialogue and explicitly unknown speakers. It rejects
missing, ambiguous or cross-document mappings before range admission. The owner
validates references before consuming the provider sequence or mutating characters.
Existing supervisor ownership and source/revision gates still reject obsolete
publications; no new queue or provider lifecycle is introduced.

Per-turn attribution evidence remains owned and serialized by the prepared
document. The delta carries bounded validation references, not a second dialogue
database. Current canonical identities/redirects still come from the existing
registry service: arbitrary neural entity reconciliation and candidate rejection
remain #125/#127 follow-up work. This adapter does not introduce ModernBookNLP or
claim improved inference accuracy. VS20–23 add independently labeled prose,
whole/split continuity, selection survival and atomic malformed-input rejection to
the existing VS01–19 baseline.

The November 5 automatic-change native probe opened the 110-word City excerpt,
retained Mara/Sophia on reopen and reached 523 ms of playback at an in-app elapsed
26.650 seconds. Selecting Sarah without Apply produced a replacement plan routed
to Sarah, but did not reach current native acknowledgment within two minutes.
The probe FAILED; it does not establish audible replacement or smooth switching.
A process sample found MLX evaluation waiting; this is not a proven root cause.
The test app received normal Quit, exited successfully, and its Python child was
absent afterward. The existing user-owned debug app was left running. Private
receipts are in the QA container's `Data/auto-voice-adapter-20261105/`; the JSON
links the source trace and audio paths. The failed run is retained for runtime
follow-up, not superseded by controller tests.
