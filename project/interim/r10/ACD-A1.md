## ACD-A1 — Revision-owned incremental attribution

> Fixed published R1 snapshot, captured November 4, 2026 Pacific.
> [Source design/plan](https://github.com/kellyjanderson/readaloud/issues/124#acd-a1--revision-owned-incremental-attribution) · [package provenance](README.md) · [lifecycle](../README.md).
> GitHub owns current execution state; this snapshot is not an implementation or acceptance claim.

Design revision R1, November 4, 2026 Pacific. Derived from [A1](https://github.com/kellyjanderson/readaloud/issues/124#a1--reproduced-attribution-boundary-failure); implementation base `1f605cfa74bc4374ffc278cb9ccb67218efe6cc4`. This is a proposed implementation contract, not a statement of implemented behavior. Global requirements and delivery rules are in [plan R10](https://github.com/kellyjanderson/readaloud/issues/110#implementation-plan-r10).

### Problem, decision and boundary
The existing public oracle produces Alice/Bob/Alice/Bob as one input and Alice/Bob/Bob/Bob across two fragments. Preserve the heuristic provider while fixing context ownership; replacing the algorithm first would confound the regression. No whole-book analysis gate and no forced alternation when evidence is ambiguous.

`DocumentImportService` will pass an immutable attribution context into `SpeakerAttributionService` and receive updated context separately from newly published outcomes. Proposed data contract: `{workId, sourceRevision, analysisRevision, sourceCursor, globalParagraphCursor, precedingResolvedTurns, openQuoteState, entityReferences, providerVersion}`. Each remembered turn contains source spans, stable character reference, rule/evidence and confidence kind. Context is evidence, never another set of publishable outcomes. Output is `{newOutcomes, contextCheckpoint, diagnostics}`; outcomes retain unknown speakers explicitly.

Keep the last two resolved dialogue turns plus the existing bounded textual neighborhood as the initial heuristic context policy. Reset alternation state at an explicit scene boundary. An oversized/unclosed quote produces a bounded provisional/unknown result rather than growing the carry indefinitely. This bound is an initial policy to verify against the corpus, not a claim that two turns solve all attribution. Global source coordinates, not fragment-relative paragraph indices, identify adjacency. Cache replay restores the matching context checkpoint or replays from the nearest valid checkpoint without duplicating published evidence.

### Ownership, migration and changes
The document-preparation worker owns context mutation; its existing supervisor owns revision admission and the eight-credit publication bound. One active context advance per document revision; out-of-order range demands cannot mutate the sequential analysis cursor. Seeking reads prepared checkpoints or requests bounded replay. Main isolate receives immutable current-revision projections only. Replacement/cancel invalidates the analysis epoch immediately; stale success, failure and checkpoint writes are discarded. Worker shutdown follows ACD-R1.

Change `document_import_service.dart`, `speaker_attribution_service.dart`, preparation messages/checkpoints and their tests. Add optional context/result DTOs while retaining existing whole-input entry points as adapters. Do not reset the session-wide cast projection introduced by #120. Preserve the prior provider behind a test adapter for comparison; do not introduce a second persistent cast store.

### Acceptance and reconciliation
Make the exact A1 oracle a permanent passing regression. Compare split/whole results at every legal boundary in a small synthetic corpus: speech tags, pronouns, >2 speakers, unknowns, scene breaks and Unicode. Verify no cross-work context, stale writes, duplicated evidence or EOF loss. Measure bounded retained context on growing input. Run existing attribution/preparation tests and held-out #89 cases; then private City turn labels in the real app. Record accuracy/coverage and errors separately from UI cast visibility.

Reconcile `character-dialogue-attribution-and-voice-casting.md`, `document-speech-pipeline.md` and `normalized-content-and-position-mapping.md` after implementation. Dependency: current integrated baseline only. Rollback: revert the bounded context patch while retaining new regression evidence; no persisted voice-choice loss.
