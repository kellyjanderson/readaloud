## ACD-C1 — Persistent work characters and voice intent

> Fixed published R1 snapshot, captured November 4, 2026 Pacific.
> [Source design/plan](https://github.com/kellyjanderson/readaloud/issues/124#acd-c1--persistent-work-characters-and-voice-intent) · [package provenance](README.md) · [lifecycle](../README.md).
> GitHub owns current execution state; this snapshot is not an implementation or acceptance claim.

Design revision R1. Basis: [C1 review](https://github.com/kellyjanderson/readaloud/issues/124#c1--persistent-work-and-character-definitions), #120's integrated exact-source persistence and Reset behavior. Proposed additive extension, not a replacement of casting or preferences.

### State and invariants
Introduce a versioned `WorkRecord` owned by the document repository: `{schemaVersion, workId, recordRevision, sourceRevisions, characters, redirects, voiceIntents}`. `workId` is opaque and persists with the work; a source digest identifies a particular revision, never the whole work. Seed legacy imports only from existing exact-source ownership evidence. A rename with verified identity may retain the work; a changed manuscript needs an existing work association or explicit user linking. Never merge by title or character name alone.

`CharacterRecord` contains stable `characterId`, names/aliases, descriptors/facts, provenance spans, provider/version, user corrections, conflicts and merge/split redirects. Keep independently queryable stated gender, inferred gender and contextual presentation. Each observation has source revision/span, confidence kind and scope; contextual presentation may differ by scene. A voice's timbre is not gender evidence. Unknowns and conflicting observations survive serialization.

`VoiceIntent` is keyed by `(workId, characterId)` and holds explicit choice or Reset tombstone, monotonically increasing intent revision, portable reference identity/digest when available, and engine-specific preset realizations. User choice outranks automatic suggestion, including when both select the same voice. Reset cannot be resurrected by stale caches. Engine incompatibility retains intent and exposes unresolved realization; it never silently selects a replacement. Alias merge preserves provenance and resolves conflicting explicit choices visibly; split creates new character IDs with explicit assignment reconciliation.

### Storage, ownership and migration
Extend `character_cast_registry.dart`, `cast_voice_assignment.dart`, `voice_assignment_coordinator.dart`, `reader_preferences_service.dart`, `reader_document_repository.dart` and serialization. Use the repository's existing immutable-generation and atomic-publication primitives for a work manifest plus append-only evidence segments; do not add SQL without a demonstrated unmet query/transaction requirement. Publish the manifest only after referenced segments exist. Single writer per work; compare expected record revision before commit. Readers consume immutable snapshots, and superseded work cannot publish through a reused document ID.

Persist comprehensive evidence on disk; send bounded projections to the UI and preparation workers. Cancel may abandon an unpublished generation but must not remove a committed work record. Shutdown waits for admitted short metadata writes or leaves a recoverable previous generation. Add a new explicit `.radoc` schema version for these fields while retaining v1/v2 reads. Migration is copy-on-write: preserve originals and exact-source preferences; ambiguous mappings remain unresolved. Older app versions must reject an unsupported new schema rather than silently dropping voice intent. A migration fixture captures choices, Reset and legacy annotations before/after.

### Acceptance and dependency
Test unfinished-book reopen, cache loss, `.radoc` export/reopen, verified move/rename, edited revision association, identical names in two works, merge/split, contradictory gender evidence, stale Reset publication and engine A/B/A. Explicit user choices survive every supported path. Reuse #120 regressions. ACD-A1 provides stable source-coordinate evidence; schema work may begin independently but integration must use that identity contract. Reconcile character architecture, reader session state and serialization guidance. Rollback keeps originals and the last valid manifest; never downgrade by deleting new fields.
