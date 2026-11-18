# Read Aloud repository workflow

This is the authoritative process. Git holds implemented architecture and versioned interim designs; GitHub holds published decisions, execution, assignments and evidence. Skills are procedures, not competing authorities.

## Directed entry

One directed owner is the default; a small fix may use one issue. Preserve unrelated WIP, use a scoped named branch and stage intentional paths. Do not concurrently edit the same checkout/index.

Read README.md, project/README.md and only [Directed work](docs/project-management.md#directed-work) in the process guide by default. Retrieve the parent (when present) and assigned issue with `ruby tools/read_issue_context.rb NUMBER`. On first assignment or a changed design revision, also read the relevant contract sections, accepted decisions and affected architecture/source/tests. Re-entry reads current blocks and changed evidence; do not reload whole bodies/comment archives. A current block indexes the contract; it never waives acceptance. Missing/stale blocks require [bounded reconciliation](docs/project-management.md#compact-issue-reads-and-updates), never assumed readiness.

Conditional procedures are part of this authority: read [authority and storage](docs/project-management.md#authority-and-storage) before changing document locations; [conditional orchestration](docs/project-management.md#conditional-orchestration) before dispatch/delegation or changing ownership/model budgets; [issue updates](docs/project-management.md#compact-issue-reads-and-updates) before writing coordination blocks; [delivery](docs/project-management.md#delivery-and-reconciliation) before PR/integration/completion; [releases](docs/project-management.md#conditional-release-delivery) before release work. Moving a rule does not change its force or approval threshold. Archives are historical references only.

## Non-negotiable product expectations

Apply the [product definition](project/product-definition.md) and [README reading expectations](README.md) to every design, implementation and acceptance decision. They are requirements, not assertions of current conformance; [issue #83](https://github.com/kellyjanderson/readaloud/issues/83) records the present gaps.

- With a document available and Play requested promptly, aim for smooth audible speech within two seconds of opening the app. Report normal app startup separately; exclude it from the brick-wall times of five seconds for a reusable .radoc load and ten seconds for a first load requiring preparation or synthesis, regardless of document size. Measure hard limits from an explicit document-load request after startup, including all preparation, additional resource setup and synthesis required by that load. Do not move document work into an unrecorded warmup or infer an unmeasured startup subtraction.
- All reading work is dynamic and incremental, including acquisition, parsing, normalization, mapping, analysis, planning, resource binding, synthesis and persistence. Character discovery is only an example. Do not require whole-document completion before first speech; maintain bounded work ahead of playback and explicit revision/cancellation ownership.
- Keep the interface responsive throughout. Pending playback must be cancellable without waiting for background work to drain; obsolete completion must not trigger speech.
- Work exceeding one or two seconds requires a dynamic progress bar with real completed-work accounting, truthful stage/total/wait states and actionable failure. No pretend progress or premature 100%.
- Automatically persist processed input to reusable `.radoc` so valid second runs skip completed preparation. Preserve inflection and other speech directions as content intent; retain the long-term publishing goal independently of current engine support.
- Prefer maintained packages and platform facilities for general-purpose infrastructure. Evaluate existing solutions before writing bespoke scheduling, queues, cancellation, caching or persistence; document the concrete unmet requirement for custom replacements. Application-specific policy and integration remain project responsibilities.

Demonstrate these expectations in the running app with launch-to-audio timing, input responsiveness, emitted-audio continuity and appropriate human listening. Unit tests, codec round trips and internal readiness flags alone cannot establish conformance. Do not silently weaken requirements to fit the current implementation or expand an already accepted release scope without its coordinator's explicit reconciliation.

## Ownership, authorization and completion

GitHub Project Status owns lifecycle; issue current blocks own coordination and exact evidence pointers. Keep execution/progress out of local ledgers and mirrored issue bodies. Draft/fixed design revisions belong in `project/interim/` under its lifecycle; `tmp/` is disposable transport, never design storage. Update architecture with implementation without presenting proposals as current behavior. GitHub outages do not create another planning authority: preserve code work, report the blocker and resume publication when access returns.

Delegation requires applicable authorization and exclusive ownership; preserve fresh-context dispatch, model/effort, Astra escalation approvals/counters and worktree rules in the conditional procedure. Separate user-owned chats require platform user authorization. Workers do not change parent scope; the coordinator resolves stale/duplicate claims and material revisions. Never take over merely because a chat is quiet.

Keep repository Actions disabled: no budget. Run bounded relevant checks locally; do not dispatch/add automatic workflows or require new remote CI. Paid execution or changing this constraint requires explicit user approval. Report passed, failed, blocked and not run distinctly. Batch meaningful checkpoints, not heartbeat comments or routine polling.

Every PR declares its actual base and links its issue plus parent when present; use `Refs` for an intermediate parent. Release slices target the assigned release/dependency branch, not main. Preserve existing branches/WIP. No merge or push directly to main, release merge or publication without explicit user authorization. This workflow is not authorization.

`Reconcile` requires accepted evidence and merged architecture/human docs; merged PRs, closed children and Project Done are insufficient. Keep missing acceptance open; never archive unfinished work. A feature integrated into its declared release branch is unreleased. Retain release branches/worktrees until the release merge is verified on local main and publication is verified.

## Execution and evidence

Every asynchronous producer names its owner, execution context, bounded queue, revision/session identity, stale success/failure handling, cancellation/timeout, shutdown and proof scenario. `async` is not CPU offload. UI state belongs on Flutter's main isolate; preparation, planning, inference, assembly and heavy I/O need explicit worker/native ownership.

Audio changes need comparable emitted-audio evidence; source tests, hashes, listening and native runtime checks answer different questions. User-facing acceptance requires the running app. Keep automatic speaker routing distinct from user assignment edits and preserve uncertainty. macOS is the current functional target; verify SDK architecture before use. Never report unrun tests as passed.

Any agent that launches the application for UI, native, audio, or acceptance testing must quit the application when that test session ends, including when the test fails or is blocked. Use the app's normal Quit action, then verify its process has exited before finishing the test or development task. Do not leave a test build running between cases. Record inability to close or verify as a test blocker. Automated test commands that launch a UI app must likewise clean up their owned process before returning.

Do not alter model assets, user data, signing or installed apps during a process-only change.
