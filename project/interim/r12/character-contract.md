## Character contract R2

November 4, 2026 Pacific, baseline `00e437d`. User direction: one character type
must expose selected voice, explicit/implicit/presented gender and the information
needed for native Fish voices. This supersedes ACD-C1 R1's separate canonical
character/voice-map shape and the ACD-A1/A2 sequencing that treated heuristic repair
and provider replacement as independent projects. Other source-coordinate,
uncertainty, native-audio and acceptance requirements remain.

### Decision: one persistent character aggregate

`Character` is the application-facing domain type, identified within a particular
work. It owns the durable character attributes and selected voice. The work owns
the collection and source-revision associations. UI, attribution integration,
casting, persistence and Fish scene construction consume that same contract.
No separate Fish character database or independently writable preference map is
added alongside it. Physical storage may use existing indexed/segmented repository
primitives; that does not create another semantic owner.

Illustrative public interface (a design contract, not implemented source):

```dart
abstract interface class Character {
  WorkId get workId;
  CharacterId get id;
  int get revision;
  String get displayName;
  Set<String> get aliases;

  GenderEvidence get explicitGender;
  GenderEvidence get implicitGender;
  ScopedPresentationEvidence get presentedGender;
  CharacterFacts get attributes;

  VoiceSelection get selectedVoice;
  CharacterSpeechProfile get speechProfile;
}
```

| Property | Meaning and preservation rule |
| --- | --- |
| `workId`, `id`, `revision` | Stable work/character identity and monotonic record revision. Source digest identifies an edition/revision, not the character. Rename/reordering does not regenerate identity. Ambiguous association between works is explicit. |
| `displayName`, `aliases` | Canonical name, observed names and durable redirects for merges. Split/merge conflicts preserve provenance and require explicit resolution where choices differ. |
| `explicitGender` | Express statements about the character, with exact evidence/source or user-authored provenance. Unknown/conflicting statements remain representable. |
| `implicitGender` | Inferences and their evidence, provider/version, confidence kind and alternatives. Never promoted silently to an explicit fact. |
| `presentedGender` | Contextual portrayal/presentation, scoped to source spans, scene or narrative time. It may differ from either other field and may change through the story. |
| `attributes` | Typed facts such as descriptions, pronouns, relationships and other character attributes, with evidence and scope. Preserve comprehensive history on disk; expose bounded evidence summaries/references to the UI. Avoid a giant untyped bag or an unbounded UI payload. |
| `selectedVoice` | The one durable selection/selection-policy value, including explicit user choice, automatic mode/Reset tombstone, provenance and selection revision. Explicit choices remain effective intent even when equal to an automatic suggestion. |
| `speechProfile` | Canonical character-level delivery defaults and references to exact-model adjustment definitions. Per-utterance emotion belongs to the turn; a temporary scene direction must not overwrite the persistent character. |

`GenderEvidence` exposes observations, a resolved value when justified, uncertainty
and conflicts. Scoped presentation resolves for the current source context. A
voice-matching hint is derived from these fields using the retained pronoun/context
policy; it cannot overwrite stated identity or infer identity from the chosen
voice. User corrections and contradictory source evidence are both retained.

### Selected voice, Fish requirements and prepared resources

`VoiceSelection` identifies a library/reference voice or an engine-specific preset.
It can retain explicit engine-specific overrides **inside the same selection
value**. It records Reset independently of absence and never erases the original
choice when an engine cannot realize it. Automatic suggestions are computed from
the character/catalog and become an explicit resolution result, not a competing
mutable copy of `selectedVoice`.

The selected library/reference entry exposes stable asset IDs, audio content
digests, transcript/text digest, language and provenance/license information.
These are the Fish/reference-conditioned inputs. They remain referenced library
assets rather than duplicated audio bytes/transcripts on every Character. A
preview and supported voice list use the same resolution rules as playback.

One resolver derives a serializable `CharacterVoiceBindingSpec` from the character
revision/selection, speech profile and exact engine/model/runtime capabilities.
It contains the selected preset or ordered reference identities, applicable
delivery/adjustment references, compatibility outcome and conditioning policy.
Extend the existing `PreparedVoiceBinding`/`ResolvedPreparedVoiceReference` for
prepared resource identity; do not create a second binding lifecycle.

Fish's **speaker slot** is local to a bounded scene and is assigned from stable
character IDs. It is not a permanent Character property: a later scene can map the
same character to another slot while keeping the same selected voice/reference.
Encoded references, prefix/KV caches and native handles belong to the resident
engine worker. Cache keys include reference content/transcript, exact model,
runtime/precision and conditioning identity. They never belong in serialized
Character data. This allows native-efficient switching without coupling character
records to Fish token syntax or preventing Qwen/MOSS/Kokoro reuse.

The current effective playing voice is a runtime acknowledgment of a captured
character/selection revision. Retain `VoiceAssignmentCoordinator` for requested
versus effective transitions, but make its maps projections of the Character
selection snapshots. It does not become a second persistent selection owner.

### Attribution providers populate the contract

Define one typed `CharacterAnalysisDelta`: work/source/analysis revision,
provider/model identity, stable source spans, proposed entity/alias associations,
attribute observations and dialogue-to-character references. Provider-native
entity IDs are mapped to stable character IDs by one shared reconciliation layer.
Neither heuristics nor ModernBookNLP assigns user voices or mutates records directly.

The work/character repository is the single writer. It validates ownership and
revision, reconciles evidence/aliases and publishes immutable current snapshots.
Explicit user choice/corrections outrank inferred changes; stale success/failure
cannot overwrite a successor work or resurrect Reset. Analysis workers own their
bounded context and off-UI compute; the existing supervisor owns cancellation,
queue bounds and shutdown. Already-playing audio retains its captured revision;
future unplayed turns may use a newly admitted analysis revision.

The split-attribution oracle remains a provider-neutral regression. It verifies
source-coordinate and fragment-continuity semantics through the common adapter,
so replacing a provider does not invalidate the test. Repair the current heuristic
only where necessary for a working fallback or first Fish slice; do not expand its
rules into a separate quality project before trying the neural provider.
ModernBookNLP is evaluated and, if qualified, integrated against this same type,
evidence merge and test contract. Its internal NLP context is still provider-owned.
A future provider swap replaces its adapter, not character storage/UI/voice logic.

### One migration, incremental delivery

1. Evolve `CastEntry`/`CharacterIdentityProfile` into the aggregate interface (or
   retain compatibility names while exposing it). Reuse existing evidence and
   immutable value objects. Separate the three gender fields without discarding
   current observations. New `Character` must not merely shadow the old writable
   registry indefinitely.
2. Migrate exact-source preferences into `Character.selectedVoice` once, including
   explicit selections equal to auto choices and Reset. Existing APIs become
   temporary projections/adapters. Version the `.radoc` schema additively, retain
   old readers/import paths as specified and preserve originals during migration.
3. Route current attribution output through the delta/merge boundary and make UI
   and scene planning consume the same character view. Keep this vertical slice
   small enough to prove one character/voice survives reopen and produces Fish audio.
4. Connect the neural provider and richer native scene use through those same
   boundaries. Do not require every possible character attribute or a full book's
   analysis before the first audible slice.

Reuse the existing document repository's generation/atomic publication facilities.
The earlier suggested append-only evidence layout is an option if actual query,
size and crash-safety needs require it, not an independent storage-framework
prerequisite. No new database/event-sourcing subsystem is implied.

### Ownership, acceptance and supersession

#126 owns the aggregate, selection ownership and one persistence migration.
#125 owns provider-neutral attribution deltas, continuity regression and any minimal
legacy fallback repair. #127 owns local provider qualification/integration against
that boundary; #111 owns derived binding/scene/native synthesis consumption.
Coordinate shared DTOs before edits; one checkout writer, no duplicate controllers
or stores. Model/runtime cancellation remains #113/#112's existing contract.

Tests must follow the same character from normal import/provider output through
registry/UI selection, serialized reopen, native scene binding and engine A/B/A.
Cover explicit/implicit/presented conflicts, source context, aliases/merge/split,
two same-named works, cache loss, Reset versus stale inference, incompatible presets
and model-specific directions. Test both attribution providers against the common
split/whole and independent prose oracles. Preserve five usable reference choices,
actual City ending/voice identity and no model reload for ordinary character turns.

Reconcile current character, reader-session, speech enrichment, engine capability
and serialization architecture only with implemented evidence. This document is
the revised design, not a claim that the new type or migration is implemented.
