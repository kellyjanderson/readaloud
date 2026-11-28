## ACD-F1 — Truthful operation state and quiet reader feedback

> Fixed published R1 snapshot, captured November 4, 2026 Pacific.
> [Source design/plan](https://github.com/kellyjanderson/readaloud/issues/119#acd-f1--truthful-operation-state-and-quiet-reader-feedback) · [package provenance](README.md) · [lifecycle](../README.md).
> GitHub owns current execution state; this snapshot is not an implementation or acceptance claim.

Design revision R1, November 4, 2026 Pacific; base `1f605cfa74bc4374ffc278cb9ccb67218efe6cc4`. Basis: UI review and implementation boundaries above; #120 copyable errors. Proposed remaining delta under [plan R10](https://github.com/kellyjanderson/readaloud/issues/110#implementation-plan-r10).

### Preserve and extend
The covering download toast is already removed; measured progress, optional Activity, fading completions and persistent snapshot lookup already exist. Reuse those controls and state owners. Complete native verification and missing acquisition cancel/resume rather than replacing the feedback UI.

Normalize producer reports into an immutable operation view: `{operationId, ownerKind, ownerEpoch, stage, state, completedUnits, totalUnits?, unit, updatedAt, error?, recoveryActions}`. States are queued/running/waiting/finalizing/succeeded/failed/cancelled. Each producer owns its counters and terminal event; UI timers may fade completed rows but cannot infer success. Epoch plus operation identity prevent stale progress/errors from reviving a cancelled row or clearing a newer operation. Terminal events are idempotent; a retry gets a new operation identity linked to the failed attempt.

### Visible behavior and concurrency
Default reader shows one primary current operation, actionable failure or ready state. Activity is opt-in detail. Active operations sort before terminal history; completed rows move below active work and fade under the existing reduced-motion policy. Errors remain selectable/copyable with retry or clear action. No routine popup duplicates the same producer report.

Only a known valid denominator produces a progress bar. Counter completion before final validation changes the stage to finalizing, not fake 100% readiness. Unknown totals show stage and real counts; waiting for read-ahead is idle demand, not endless work. Do not smooth percentages by inventing completed units. The highest-priority reader-blocking operation owns the summary; unrelated background completion cannot replace a current failure.

Add distinct model-download Cancel/Resume through acquisition ownership. Cancel document does not cancel an unrelated installed-model validation or delete cached weights. UI receives projections on the main isolate; workers own I/O and progress production. Coalesce intermediate progress to bounded latest-state delivery while guaranteeing terminal delivery. Activity retains a bounded in-memory recent history; diagnostics may export detailed receipts separately. On close, cancel UI timers/subscriptions and let ACD-R1/M1 shut down owned producers.

### Changes, migration and proof
Extend `preparation_status.dart` (including its existing `MeasuredProgress`), controller/app settings and existing worker progress envelopes. Preserve user Activity preference and #120 accumulated cast/copyable error behavior. No new persistent task database and no second event bus. Library decision: retain existing Flutter semantics/animation and shared measured control; application-specific stage/owner projection remains local policy.

Test terminal delivery, duplicate events, stale failure after retry, unknown/changing totals, finalize-after-byte-completion and cancel/resume using producer fakes. Then run the actual app: download progress unobscured, offline ready state, narrow window/large text, keyboard access, reduced motion, persistent recoverable error and no indicator left active after producer exit. Verify real file counts against UI; a widget-only pass is insufficient. Reconcile reader-interface architecture and reading/development guides. Depends on M1 acquisition event contract, but UI checks can begin on the integrated implementation. Rollback keeps existing measured feedback and persistent model storage.

### Source and reconciliation anchors

Pinned existing owners, not implementation of this ACD. Additional exact locations and test matrices remain in the linked review findings.

- [lib/src/widgets/preparation_status.dart](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/lib/src/widgets/preparation_status.dart)
- [lib/src/controllers/reader_controller.dart](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/lib/src/controllers/reader_controller.dart)
- [project/architecture/reader-interface-and-session-state.md](https://github.com/kellyjanderson/readaloud/blob/1f605cfa74bc4374ffc278cb9ccb67218efe6cc4/project/architecture/reader-interface-and-session-state.md)
